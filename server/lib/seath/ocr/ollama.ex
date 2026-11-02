defmodule Seath.OCR.Ollama do
  @moduledoc """
  Ollama OCR provider.

  Uses a vision model for high-accuracy text extraction — configured explicitly via
  Settings or OLLAMA_OCR_MODEL env var (default: "minicpm-v").
  Recommended local vision models:
    ollama pull minicpm-v         (top OCR accuracy, tables & dense text)
    ollama pull deepseek-ocr      (dedicated document OCR)
    ollama pull glm-ocr           (lightweight dedicated OCR)

  For PDFs, uses an accuracy-first adaptive pipeline:
    - If the PDF contains a rich native digital text layer (`pdftotext -layout`),
      it preserves the exact digital characters and only runs Vision OCR on
      significant embedded images (> 20 KB, skipping tiny icons/logos) so
      attached scans (like a CNH or receipt) are captured without duplicating
      the page text.
    - If the PDF is a scanned/raster document (sparse or empty digital text),
      it renders pages at 300 DPI (`pdftoppm`) and runs deterministic
      (temperature 0.0) Vision OCR per page.
  """
  @behaviour Seath.OCR.Provider

  @image_extensions ~w(.png .jpg .jpeg .tiff .bmp)
  @min_digital_text_chars 120
  @min_embedded_image_bytes 20_480

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])

    base_url =
      Keyword.get(config, :base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model =
      Keyword.get(config, :model) ||
        System.get_env("OLLAMA_OCR_MODEL", "minicpm-v")

    ext = file_path |> Path.extname() |> String.downcase()

    if ext in @image_extensions or raw_image_file?(file_path) do
      extract_image(file_path, base_url, model)
    else
      extract_pdf(file_path, base_url, model)
    end
  end

  defp raw_image_file?(file_path) do
    case File.open(file_path, [:read, :binary], fn io -> IO.binread(io, 8) end) do
      {:ok, <<0x89, "PNG", "\r\n", 0x1A, "\n">>} -> true
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> true
      {:ok, <<"II*", 0, _::binary>>} -> true
      {:ok, <<"MM", 0, "*", _::binary>>} -> true
      {:ok, <<"RIFF", _::binary>>} -> true
      _ -> false
    end
  end

  # --- Image extraction ---

  defp extract_image(file_path, base_url, model) do
    with {:ok, data} <- File.read(file_path) do
      send_to_ollama(Base.encode64(data), base_url, model)
    end
  end

  # --- PDF extraction ---

  defp extract_pdf(file_path, base_url, model) do
    case extract_pdf_text(file_path) do
      {:ok, digital_text} when byte_size(digital_text) >= @min_digital_text_chars ->
        # Digital PDF with native text layer: keep exact digital text and only
        # OCR substantial embedded images (e.g. scanned ID/receipt pasted in).
        embedded = extract_embedded_images(file_path, base_url, model)
        merge_result({:ok, digital_text}, embedded, "\n\n--- Embedded images ---\n\n")

      {:ok, sparse_text} ->
        # Scanned/raster PDF: render full pages at 300 DPI and run Vision OCR
        # (do not run pdfimages separately, as pdftoppm already renders the scan in context)
        rendered = extract_pdf_via_vision(file_path, base_url, model)
        merge_result({:ok, sparse_text}, rendered, "\n\n--- Rendered pages ---\n\n")

      {:error, _} = err ->
        rendered = extract_pdf_via_vision(file_path, base_url, model)
        merge_result(err, rendered, "\n\n--- Rendered pages ---\n\n")
    end
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

  # Extract embedded images from PDF using pdfimages at their native resolution,
  # filtering out tiny icons, logos, and decorative borders (< 20 KB) by default.
  defp extract_embedded_images(file_path, base_url, model, min_bytes \\ @min_embedded_image_bytes) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_img_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    case System.cmd("pdfimages", ["-png", file_path, Path.join(tmp_dir, "img")]) do
      {_, 0} ->
        images =
          tmp_dir
          |> Path.join("*.png")
          |> Path.wildcard()
          |> Enum.filter(&substantial_image?(&1, min_bytes))
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

  defp substantial_image?(path, min_bytes) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size >= min_bytes
      _ -> false
    end
  end

  defp extract_pdf_text(file_path) do
    case System.cmd("pdftotext", ["-layout", file_path, "-"]) do
      {text, 0} ->
        trimmed = String.trim(text)
        {:ok, trimmed}

      {error, _exit_code} ->
        {:error, error}
    end
  end

  # Convert PDF pages to images at 300 DPI and OCR each via vision model.
  # Note: pdftoppm's last argument is an output *prefix* (e.g. "#{tmp_dir}/page"),
  # which produces "#{tmp_dir}/page-1.png", "#{tmp_dir}/page-2.png", etc.
  defp extract_pdf_via_vision(file_path, base_url, model) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_ocr_#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)
    output_prefix = Path.join(tmp_dir, "page")

    # 300 DPI provides high quality for OCR without excessive file sizes
    case System.cmd("pdftoppm", ["-png", "-r", "300", file_path, output_prefix]) do
      {_, 0} ->
        pages =
          tmp_dir
          |> Path.join("page*.png")
          |> Path.wildcard()
          |> Enum.sort()

        if pages == [] do
          File.rm_rf!(tmp_dir)
          fallback_pdfimages_ocr(file_path, base_url, model)
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
            case fallback_pdfimages_ocr(file_path, base_url, model) do
              {:ok, text} when text != "" -> {:ok, text}
              _ -> {:error, {:pdf_conversion_failed, error}}
            end
        end
    end
  end

  defp fallback_pdfimages_ocr(file_path, base_url, model) do
    case extract_embedded_images(file_path, base_url, model, 1_024) do
      {:ok, text} when text != "" -> {:ok, text}
      _ -> {:error, :no_pages_to_ocr}
    end
  end

  # --- Vision LLM call ---

  defp send_to_ollama(image_b64, base_url, model) do
    language = Application.get_env(:seath, :document_language, "Portuguese")

    body = %{
      model: model,
      stream: false,
      options: %{temperature: 0.0, num_ctx: 8192},
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
