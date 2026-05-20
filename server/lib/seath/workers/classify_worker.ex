defmodule Seath.Workers.ClassifyWorker do
  @moduledoc """
  Oban worker that classifies a document using the configured LLM provider.

  Fetches the document, validates OCR text is present, runs classification,
  applies tags/document type, and transitions the document to awaiting_review.
  """
  use Oban.Worker, queue: :classify, max_attempts: 3

  alias Seath.Documents
  alias Seath.Tags
  alias Seath.DocumentTypes

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, doc} <- fetch_document(id),
         {:ok, _text} <- validate_ocr_text(doc),
         tags <- Tags.list_tags() |> Enum.map(& &1.name),
         types <- DocumentTypes.list_types() |> Enum.map(& &1.name),
         {:ok, result} <- Seath.LLM.classify(doc.ocr_text, tags, types),
         {:ok, doc} <- apply_classification(doc, result) do
      Phoenix.PubSub.broadcast(
        Seath.PubSub,
        "documents",
        {:document_updated, %{id: doc.id, status: "awaiting_review"}}
      )

      :ok
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  defp validate_ocr_text(doc) do
    if is_nil(doc.ocr_text) or doc.ocr_text == "" do
      {:error, :no_ocr_text}
    else
      {:ok, doc.ocr_text}
    end
  end

  defp apply_classification(doc, result) do
    # Update title and confidence
    {:ok, doc} =
      Documents.update_document(doc, %{title: result.title, confidence: result.confidence})

    # Add proposed tags
    Enum.each(result.tags, fn tag_name ->
      case Tags.get_tag_by_name(tag_name) do
        nil ->
          {:ok, tag} = Tags.create_tag(%{name: tag_name})
          Tags.add_tag_to_document(doc, tag)

        tag ->
          Tags.add_tag_to_document(doc, tag)
      end
    end)

    # Set document type if matched
    doc =
      if result.document_type do
        case DocumentTypes.get_type_by_name(result.document_type) do
          nil ->
            doc

          type ->
            {:ok, updated} = Documents.update_document(doc, %{document_type_id: type.id})
            updated
        end
      else
        doc
      end

    # Transition to awaiting_review
    Documents.transition_status(doc, "awaiting_review")
  end
end
