defmodule Seath.Workers.OCRWorker do
  @moduledoc """
  Oban worker that performs OCR on a document.

  Fetches the document, runs OCR extraction, and stores the result.
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
        Logger.error("""
        No OCR provider configured.

        Set OCR_PROVIDER env var to one of:
          - "azure"  (requires AZURE_DI_ENDPOINT and AZURE_DI_KEY)
          - "ollama" (requires OLLAMA_BASE_URL, default: http://localhost:11434)
        """)
        {:discard, :not_configured}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, "document not found: #{id}"}
      document -> {:ok, document}
    end
  end
end
