defmodule Seath.OCR.Ollama do
  @moduledoc """
  Ollama OCR provider.

  Uses a vision model (default: glm-ocr, fallback: llama3.2-vision) for
  high-quality text extraction. For PDFs, extracts digital text via
  `pdftotext` AND renders pages to images for vision OCR, then merges
  both results — ensuring text in embedded images is never missed.

  This approach differentiates Seath from Paperless (which uses Tesseract):
  vision AI understands document context, handles complex layouts, and
  accurately reads text that traditional OCR struggles with.

  Requires a running Ollama instance with a vision model pulled.
  `pdftotext` and `pdftoppm` come from poppler-utils.
  """
  @behaviour Seath.OCR.Provider

  @image_extensions ~w(.png .jpg .jpeg .tiff .bmp)

  @doc """
  Best available models for OCR, in preference order.
  These are known to produce excellent text extraction results.

  Recommended (ollama pull <name>):
    qwen2.5-vl:7b   — current best open-source for OCR
    llama3.2-vision  — strong all-around vision model
    glm-ocr          — dedicated OCR model
    minicpm-v        — good OCR in a smaller package
  """
  @preferred_models ~w(qwen2.5-vl llama3.2-vision glm-ocr minicpm-v gemma3)

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])

    base_url =
      Keyword.get(config, :base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model =
      Keyword.get(config, :model) ||
        System.get_env("OLLAMA_OCR_MODEL") ||
        first_available_model(base_url)

    ext = file_path |> Path.extname() |> String.downcase()

    if ext in @image_extensions do
      extract_image(file_path, base_url, model)
    else
      extract_pdf(file_path, base_url, model)
    end
  end

  # Pick the first model from @preferred_models that's available in Ollama.
  # Strips the :tag suffix since Ollama returns "model:latest" but we
  # match against bare names like "glm-ocr".
  defp first_available_model(base_url) do
    available =
      base_url
      |> list_ollama_models()
      |> Enum.map(fn name -> name |> String.split(":") |> hd() end)
      |> MapSet.new()

    Enum.find_value(@preferred_models, fn model ->
      if MapSet.member?(available, model), do: model
    end) || "llava"
  end

  defp list_ollama_models(base_url) do
    case Req.get("#{base_url}/api/tags", receive_timeout: 2000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        Enum.map(models, & &1["name"])

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # --- Image extraction ---

  defp extract_image(file_path, base_url, model) do
    with {:ok, data} <- File.read(file_path) do
      send_to_ollama(Base.encode64(data), base_url, model)
    end
  end

  # --- PDF extraction ---

  # For PDFs: ALWAYS run both pdftotext (digital layers) AND pdftoppm+vision
  # (image layers), then merge. This ensures text in embedded images is
  # never lost — the core improvement over Paperless's Tesseract-only approach.
  defp extract_pdf(file_path, base_url, model) do
    digital = extract_pdf_text(file_path)
    vision = extract_pdf_via_vision(file_path, base_url, model)

    merge_results(digital, vision)
  end

  defp merge_results({:ok, digital}, {:ok, vision}) do
    {:ok, "#{digital}\n\n--- Image-extracted content ---\n\n#{vision}"}
  end

  defp merge_results({:ok, digital}, {:error, _}) do
    {:ok, digital}
  end

  defp merge_results({:error, _}, {:ok, vision}) do
    {:ok, vision}
  end

  defp merge_results({:error, reason}, {:error, _}) do
    {:error, reason}
  end

  defp extract_pdf_text(file_path) do
    case System.cmd("pdftotext", [file_path, "-"]) do
      {text, 0} ->
        trimmed = String.trim(text)
        {:ok, trimmed}

      {error, _exit_code} ->
        {:error, error}
    end
  end

  # Convert PDF pages to images at 300 DPI and OCR each via vision model
  defp extract_pdf_via_vision(file_path, base_url, model) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_ocr_#{Ecto.UUID.generate()}")

    # 300 DPI provides good quality for OCR without excessive file sizes
    case System.cmd("pdftoppm", ["-png", "-r", "300", file_path, tmp_dir]) do
      {_, 0} ->
        pages =
          tmp_dir
          |> Path.join("*")
          |> Path.wildcard()
          |> Enum.sort()

        if pages == [] do
          File.rm_rf!(tmp_dir)
          {:error, :no_pages_to_ocr}
        else
          texts =
            Enum.map(pages, fn page_path ->
              case extract_image(page_path, base_url, model) do
                {:ok, text} -> text
                {:error, _} -> ""
              end
            end)

          File.rm_rf!(tmp_dir)

          combined = texts |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n--- Page ---\n\n")

          if combined == "" do
            {:error, :no_text_extracted}
          else
            {:ok, combined}
          end
        end

      {error, _exit_code} ->
        File.rm_rf!(tmp_dir)

        cond do
          String.contains?(error, "not found") ->
            {:error, "pdftoppm not found. Install poppler-utils for scanned PDF support."}

          true ->
            {:error, {:pdf_conversion_failed, error}}
        end
    end
  end

  # --- Vision LLM call ---

  defp send_to_ollama(image_b64, base_url, model) do
    language = Application.get_env(:seath, :document_language, "Portuguese")

    body = %{
      model: model,
      stream: false,
      messages: [
        %{
          role: "user",
          content: ocr_prompt(language),
          images: [image_b64]
        }
      ]
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, String.trim(content)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  defp ocr_prompt(language) do
    """
    TRANSCRIPTION INSTRUCTIONS (this is an OCR task):

    Transcribe EVERY word, number, and symbol visible in this image.
    The document is in #{language}.

    Rules:
    - Output ONLY the raw text as it appears. No summaries, no descriptions.
    - Preserve line breaks and paragraph spacing.
    - Do NOT use markdown formatting (no **bold**, no `code`, no headings).
    - Include headers, footers, page numbers, and fine print.
    - Pay special attention to: numbers, dates, monetary amounts, tax IDs,
      company names, and proper names.
    - If text is in a table, maintain the row/column structure with spaces or tabs.
    - If something is illegible, write [illegible] and continue.
    - Transcribe everything from top to bottom — do not stop early.
    """
  end
end
