defmodule Seath.Workers.OCRWorker do
  @moduledoc """
  Oban worker that performs OCR on a document.

  Fetches the document, runs OCR extraction, and stores the result.
  On failure, marks the document as error with a descriptive message.
  """
  use Oban.Worker, queue: :ocr, max_attempts: 3

  alias Seath.Documents
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, document} <- fetch_document(id),
         {:ok, text} <- Seath.OCR.extract(document.file_path),
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
        msg = "OCR provider unreachable. Check that Ollama is running."
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
end
