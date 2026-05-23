defmodule Seath.OCR.Ollama do
  @moduledoc """
  Ollama OCR provider.

  For PDF documents, first tries to extract embedded text via `pdftotext`
  (most PDFs already have selectable text). Falls back to a vision model
  for scanned/image-only PDFs.

  For images (PNG, JPG, etc.), sends directly to the vision model.

  Requires a running Ollama instance with a vision model pulled.
  `pdftotext` comes from poppler-utils (included in the Nix dev shell).
  """
  @behaviour Seath.OCR.Provider

  @image_extensions ~w(.png .jpg .jpeg .tiff .bmp)

  @impl true
  def extract(file_path) do
    config = Application.get_env(:seath, __MODULE__, [])

    base_url =
      Keyword.get(config, :base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model = Keyword.get(config, :model) || System.get_env("OLLAMA_OCR_MODEL", "llava")

    ext = file_path |> Path.extname() |> String.downcase()

    if ext in @image_extensions do
      extract_image(file_path, base_url, model)
    else
      extract_pdf(file_path, base_url, model)
    end
  end

  # For image files, send directly to Ollama vision model
  defp extract_image(file_path, base_url, model) do
    with {:ok, data} <- File.read(file_path) do
      send_to_ollama(Base.encode64(data), base_url, model)
    end
  end

  # For PDFs: extract digital text first, then check if pages are missing text.
  # If pdftotext returns very little text relative to page count, the PDF likely
  # has scanned/image pages — run vision OCR on those pages and merge.
  defp extract_pdf(file_path, base_url, model) do
    digital = extract_pdf_text(file_path)

    case {digital, get_pdf_page_count(file_path)} do
      {{:ok, text}, {:ok, page_count}} when text != "" and byte_size(text) < page_count * 100 ->
        # Low text density — pages likely contain images. Run vision OCR and merge.
        case extract_pdf_via_vision(file_path, base_url, model) do
          {:ok, vision} ->
            {:ok, "#{text}\n\n--- Additional OCR-extracted content ---\n\n#{vision}"}
          {:error, _} ->
            {:ok, text}
        end

      {{:ok, text}, _} when text != "" ->
        # Plenty of digital text — use it directly
        {:ok, text}

      _ ->
        # No digital text at all — use vision OCR
        extract_pdf_via_vision(file_path, base_url, model)
    end
  end

  defp get_pdf_page_count(file_path) do
    case System.cmd("pdfinfo", [file_path]) do
      {output, 0} ->
        case Regex.run(~r/Pages:\s+(\d+)/, output) do
          [_, pages] -> {:ok, String.to_integer(pages)}
          nil -> {:error, :no_page_count}
        end

      _ ->
        {:error, :pdfinfo_failed}
    end
  end

  # Extract embedded text from PDF using pdftotext
  defp extract_pdf_text(file_path) do
    case System.cmd("pdftotext", [file_path, "-"]) do
      {text, 0} ->
        trimmed = String.trim(text)
        {:ok, trimmed}

      {error, _exit_code} ->
        {:error, error}
    end
  end

  # Convert PDF pages to images and OCR via vision model
  defp extract_pdf_via_vision(file_path, base_url, model) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_ocr_#{Ecto.UUID.generate()}")

    case System.cmd("pdftoppm", ["-png", "-r", "200", file_path, tmp_dir]) do
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

  defp send_to_ollama(image_b64, base_url, model) do
    language = Application.get_env(:seath, :document_language, "Portuguese")

    body = %{
      model: model,
      stream: false,
      messages: [
        %{
          role: "user",
          content: """
          Just transcribe the text in this image and preserve the formatting and layout (high quality OCR).
          Do that for ALL the text in the image. Be thorough and pay attention. This is very important.
          The image is from a text document so be sure to continue until the bottom of the page.
          The document is likely in #{language}.
          Thanks a lot! You tend to forget about some text in the image so please focus!
          Pay special attention to monetary amounts, totals, invoice numbers, dates, tax IDs (CNPJ/CPF), and company names.
          Use markdown format but without a code block.
          """,
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
end
