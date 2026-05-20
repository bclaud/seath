defmodule Seath.Workers.EmbedWorker do
  @moduledoc """
  Oban worker that generates and stores document embeddings.

  Fetches an archived document, generates an embedding vector from its OCR text
  using the configured LLM provider, and stores it in the `document_embeddings` table.
  """
  use Oban.Worker, queue: :classify, max_attempts: 3

  alias Seath.Documents

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, doc} <- fetch_document(id),
         {:ok, _text} <- validate_ocr_text(doc),
         {:ok, vector} <- Seath.LLM.embed(doc.ocr_text) do
      Seath.Embeddings.store_embedding!(doc.id, vector, configured_model())
      :ok
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  defp validate_ocr_text(%{ocr_text: text}) when not is_nil(text) and text != "", do: {:ok, text}

  defp validate_ocr_text(_), do: {:error, :no_ocr_text}

  defp configured_model do
    Application.get_env(:seath, Seath.LLM.Ollama, [])
    |> Keyword.get(:model, "llama3.2")
  end
end
