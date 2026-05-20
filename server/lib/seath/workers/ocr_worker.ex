defmodule Seath.Workers.OCRWorker do
  @moduledoc """
  Oban worker that performs OCR on a document.

  Fetches the document, runs OCR extraction, and stores the result.
  """
  use Oban.Worker, queue: :ocr, max_attempts: 3

  alias Seath.Documents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, document} <- fetch_document(id),
         {:ok, text} <- Seath.OCR.extract(document.file_path),
         {:ok, _updated} <- Documents.store_ocr_text(document, text) do
      Seath.Workers.ClassifyWorker.new(%{"document_id" => document.id}) |> Oban.insert()
      :ok
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, "document not found: #{id}"}
      document -> {:ok, document}
    end
  end
end
