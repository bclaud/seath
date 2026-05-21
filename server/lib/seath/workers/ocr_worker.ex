defmodule Seath.Workers.OCRWorker do
  @moduledoc """
  Oban worker that performs OCR on a document.

  Fetches the document, runs OCR extraction, and stores the result.
  Supports two modes:
    1. **Vision LLM OCR** — if the configured LLM provider supports `ocr_vision/2`,
       uses the LLM's vision model for higher-quality extraction that captures
       structured data (amounts, invoice numbers, dates, tax IDs).
    2. **Standard OCR** — falls back to the configured OCR provider (Azure or Ollama).

  On failure, marks the document as error with a descriptive message.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 3

  alias Seath.Documents
  require Logger

  @image_extensions ~w(.png .jpg .jpeg .tiff .bmp)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, document} <- fetch_document(id),
         {:ok, text} <- extract_text(document),
         {:ok, _updated} <- Documents.store_ocr_text(document, text) do
      Phoenix.PubSub.broadcast(
        Seath.PubSub,
        "documents",
        {:document_updated, %{id: document.id, status: "processing"}}
      )

      Seath.Workers.ClassifyWorker.new(%{"document_id" => document.id}) |> Oban.insert()
      :ok
    else
      {:error, :not_configured} ->
        msg = "No OCR provider configured. Go to Settings to configure one."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :not_configured}

      {:error, :connection_refused} ->
        msg = "OCR provider unreachable. Check that the service is running."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :connection_refused}

      {:error, {:unexpected_response, 500, body}} ->
        msg = "OCR failed: #{inspect(body)}"
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :ocr_failed}

      {:error, reason} ->
        msg = "OCR error: #{inspect(reason)}"
        Logger.error(msg)
        mark_error(id, msg)
        {:error, reason}
    end
  end

  defp mark_error(document_id, message) do
    case Documents.get_document(document_id) do
      nil -> :ok
      doc -> Documents.mark_as_error(doc, message)
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, "document not found: #{id}"}
      document -> {:ok, document}
    end
  end

  defp extract_text(%{file_path: file_path} = _document) do
    if use_vision_ocr?() do
      extract_via_vision(file_path)
    else
      Seath.OCR.extract(file_path)
    end
  end

  defp use_vision_ocr? do
    # Vision LLM OCR is opt-in via config. Set `config :seath, :ocr_use_vision_llm, true`
    # OR set `OLLAMA_VISION_MODEL` environment variable.
    configured? =
      Application.get_env(:seath, :ocr_use_vision_llm, false) ||
        not is_nil(System.get_env("OLLAMA_VISION_MODEL"))

    configured? && vision_available?()
  end

  defp vision_available? do
    provider = Seath.LLM.impl()

    provider != nil and
      function_exported?(provider, :ocr_vision, 2)
  end

  defp extract_via_vision(file_path) do
    ext = file_path |> Path.extname() |> String.downcase()

    if ext in @image_extensions do
      extract_image_via_vision(file_path)
    else
      extract_pdf_via_vision(file_path)
    end
  end

  defp extract_image_via_vision(file_path) do
    vision_prompt = """
    Transcribe ALL text from this document image. Pay special attention to:
    - Monetary amounts and totals
    - Invoice/receipt numbers
    - Dates (issue date, due date)
    - Tax IDs and company registration numbers
    - Names of people and companies
    - Product descriptions and quantities
    """

    with {:ok, image_data} <- File.read(file_path),
         {:ok, text} <- Seath.LLM.ocr_vision(image_data, prompt: vision_prompt) do
      {:ok, text}
    end
  end

  defp extract_pdf_via_vision(file_path) do
    # First try pdftotext for embedded text
    case extract_pdf_text(file_path) do
      {:ok, text} when text != "" and text != nil ->
        {:ok, text}

      _ ->
        # Fall back to converting PDF pages to images and OCR via vision
        convert_pdf_pages_and_ocr(file_path)
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

  defp convert_pdf_pages_and_ocr(file_path) do
    tmp_dir = Path.join(System.tmp_dir!(), "seath_vocr_#{Ecto.UUID.generate()}")

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
              case File.read(page_path) do
                {:ok, image_data} ->
                  vision_prompt = """
                  Transcribe ALL text from this document page. Pay special attention to:
                  - Monetary amounts and totals
                  - Invoice/receipt numbers
                  - Dates (issue date, due date)
                  - Tax IDs and company registration numbers
                  - Names of people and companies
                  - Product descriptions and quantities
                  """

                  case Seath.LLM.ocr_vision(image_data, prompt: vision_prompt) do
                    {:ok, text} -> text
                    {:error, _} -> ""
                  end

                {:error, _} ->
                  ""
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
end
