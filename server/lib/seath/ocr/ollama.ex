defmodule Seath.OCR.Ollama do
  @moduledoc """
  Ollama OCR provider.

  Uses a vision model for text extraction — configured explicitly via
  Settings or OLLAMA_OCR_MODEL env var (default: "llava").
  Users should pull a capable vision model:
    ollama pull llama3.2-vision   (good all-around)
    ollama pull qwen2.5-vl:7b     (excellent OCR)
    ollama pull glm-ocr           (dedicated OCR model)

  For PDFs, extracts digital text via pdftotext AND renders pages to
  images for vision OCR, then merges both results — ensuring text in
  embedded images (like scanned CNH pasted into a document) is captured.
  """
  @behaviour Seath.OCR.Provider

  @image_extensions ~w(.png .jpg .jpeg .tiff .bmp)

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])

    base_url =
      Keyword.get(config, :base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model =
      Keyword.get(config, :model) ||
        System.get_env("OLLAMA_OCR_MODEL", "llava")

    ext = file_path |> Path.extname() |> String.downcase()

    if ext in @image_extensions do
      extract_image(file_path, base_url, model)
    else
      extract_pdf(file_path, base_url, model)
    end
  end

  # --- Image extraction ---

  defp extract_image(file_path, base_url, model) do
    with {:ok, data} <- File.read(file_path) do
      send_to_ollama(Base.encode64(data), base_url, model)
    end
  end

  # --- PDF extraction ---

  # Three-pass extraction pipeline (inspired by docling-serve's approach):
  #   1. pdftotext      — extracts digital text layers (surrounding text)
  #   2. pdfimages      — extracts embedded images at NATIVE resolution
  #                       (catches scanned CNH, photos, etc. at full quality)
  #   3. pdftoppm+vision — renders pages as images and OCRs them
  #                       (catches any remaining non-embedded visual text)
  # All results are merged to ensure nothing is missed.
  defp extract_pdf(file_path, base_url, model) do
    digital = extract_pdf_text(file_path)
    embedded = extract_embedded_images(file_path, base_url, model)
    rendered = extract_pdf_via_vision(file_path, base_url, model)

    digital
    |> merge_result(embedded, "\n\n--- Embedded images ---\n\n")
    |> merge_result(rendered, "\n\n--- Rendered pages ---\n\n")
  end

  # Merge two extraction results:
  # - If both have content, concatenate with separator
  # - If one is empty/errored but the other has content, use the content
  # - If both are empty/errored, propagate the first error or :no_text_extracted
  defp merge_result({:ok, b}, {:ok, e}, sep) when e != "" and b != "",
    do: {:ok, "#{b}#{sep}#{e}"}

  defp merge_result({:ok, ""}, {:ok, e}, _sep) when e != "", do: {:ok, e}
  defp merge_result({:ok, b}, _extra, _sep) when b != "", do: {:ok, b}

  defp merge_result({:ok, ""}, {:ok, ""}, _sep), do: {:error, :no_text_extracted}
  defp merge_result({:ok, ""}, {:error, r}, _sep), do: {:error, r}
  defp merge_result({:error, r}, {:ok, ""}, _sep), do: {:error, r}
  defp merge_result({:error, r}, {:error, _}, _sep), do: {:error, r}

  # Extract embedded images from PDF using pdfimages at their native resolution.
  # This is critical for documents where valuable content (like a scanned CNH)
  # is embedded as an image within the PDF — the model gets the full-resolution
  # image directly instead of a tiny region within a rendered page.
  defp extract_embedded_images(file_path, base_url, model) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_img_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    case System.cmd("pdfimages", ["-all", file_path, "#{tmp_dir}/img"]) do
      {_, 0} ->
        images =
          tmp_dir
          |> Path.join("*")
          |> Path.wildcard()
          |> Enum.reject(fn p -> Path.extname(p) in ~w(.txt .xml) end)
          |> Enum.sort()

        if images == [] do
          File.rm_rf!(tmp_dir)
          {:ok, ""}
        else
          texts =
            Enum.map(images, fn img_path ->
              case extract_image(img_path, base_url, model) do
                {:ok, text} -> text
                {:error, _} -> ""
              end
            end)

          File.rm_rf!(tmp_dir)

          combined =
            texts |> Enum.reject(&(&1 == "")) |> Enum.join("\n\n--- Embedded Image ---\n\n")

          {:ok, combined}
        end

      {_err, _code} ->
        File.rm_rf!(tmp_dir)
        {:ok, ""}
    end
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
