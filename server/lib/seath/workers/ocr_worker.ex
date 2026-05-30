defmodule Seath.Workers.OCRWorker do
  @moduledoc """
  Oban worker that performs OCR on a document.

  Fetches the document, runs OCR extraction via the configured OCR provider
  (Azure Document Intelligence or Ollama vision model), stores the result,
  and enqueues the classification worker.

  On failure, marks the document as error with a descriptive message.
  """

  use Oban.Worker, queue: :ocr, max_attempts: 3

  alias Seath.Documents
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    try do
      with {:ok, document} <- fetch_document(id),
           {:ok, text} <- Seath.OCR.extract(document.file_path),
           :ok <- validate_text(text),
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

        {:error, {:unexpected_response, _status, body}} ->
          msg = "OCR failed: #{inspect(body)}"
          Logger.error(msg)
          mark_error(id, msg)
          {:discard, :ocr_failed}

        {:error, :no_text_extracted} ->
          msg = "OCR returned no text. Check that the OCR model is working."
          Logger.error(msg)
          mark_error(id, msg)
          {:discard, :no_text_extracted}

        {:error, :empty_text} ->
          msg = "OCR returned empty text. Check that the OCR model is working."
          Logger.error(msg)
          mark_error(id, msg)
          {:discard, :empty_text}

        {:error, reason} ->
          msg = "OCR error: #{inspect(reason)}"
          Logger.error(msg)
          mark_error(id, msg)
          {:discard, reason}
      end
    rescue
      e ->
        msg = "Unexpected OCR error: #{Exception.message(e)}"
        Logger.error(msg)
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        mark_error(id, msg)
        {:discard, :exception}
    end
  end

  defp validate_text(text) when is_binary(text) and text != "", do: :ok
  defp validate_text(_), do: {:error, :empty_text}

  defp mark_error(document_id, message) do
    case Documents.get_document(document_id) do
      nil ->
        :ok

      doc ->
        Documents.mark_as_error(doc, message)

        Phoenix.PubSub.broadcast(
          Seath.PubSub,
          "documents",
          {:document_updated, %{id: doc.id, status: "error", error_message: message}}
        )
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, "document not found: #{id}"}
      document -> {:ok, document}
    end
  end
end
