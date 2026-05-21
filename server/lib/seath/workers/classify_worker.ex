defmodule Seath.Workers.ClassifyWorker do
  @moduledoc """
  Oban worker that classifies a document using the LLM.

  Fetches the document, validates OCR text is present, runs classification
  (which now extracts title, document_type, tags, correspondent, and
  involved parties in a single JSON call), applies the results, and
  transitions the document to awaiting_review.

  On failure, marks the document as error with a descriptive message.
  """
  use Oban.Worker, queue: :classify, max_attempts: 3

  alias Seath.Documents
  alias Seath.Tags
  alias Seath.DocumentTypes
  alias Seath.Correspondents
  alias Seath.InvolvedParties
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, doc} <- fetch_document(id),
         {:ok, text} <- validate_ocr_text(doc),
         {:ok, result} <- classify(text),
         {:ok, doc} <- apply_classification(doc, result) do
      Phoenix.PubSub.broadcast(
        Seath.PubSub,
        "documents",
        {:document_updated, %{id: doc.id, status: "awaiting_review"}}
      )

      :ok
    else
      {:error, :not_configured} ->
        msg = "No LLM provider configured. Go to Settings to configure one."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :not_configured}

      {:error, :connection_refused} ->
        msg = "LLM provider unreachable. Check that Ollama is running."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :connection_refused}

      {:error, :no_ocr_text} ->
        msg = "Document has no OCR text. OCR may have failed."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :no_ocr_text}

      {:error, reason} ->
        msg = "Classification error: #{inspect(reason)}"
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

  defp classify(text) do
    # Load available tags, types, correspondents once
    tags = Tags.list_tags()
    types = DocumentTypes.list_types()

    tag_names = Enum.map(tags, & &1.name)
    type_names = Enum.map(types, & &1.name)

    Seath.LLM.classify(text, tag_names, type_names)
  end

  defp apply_classification(doc, result) do
    # Update document title and confidence
    {:ok, doc} =
      Documents.update_document(doc, %{title: result.title, confidence: result.confidence})

    # Apply document type — validate against existing types (case-insensitive)
    doc = apply_document_type(doc, result.document_type)

    # Apply tags — validate against existing, create new ones if needed
    doc = apply_tags(doc, result.tags)

    # Apply correspondent — match against existing (case-insensitive), don't auto-create
    doc = apply_correspondent(doc, Map.get(result, :correspondent))

    # Apply involved parties — create entries for extracted entities
    apply_involved_parties(doc, Map.get(result, :involved_parties, []))

    # Transition to awaiting_review
    Documents.transition_status(doc, "awaiting_review")
  end

  defp apply_tags(doc, tag_names) when is_list(tag_names) do
    # Load all tags once for validation
    existing_tags = Tags.list_tags()
    existing_lower = Map.new(existing_tags, fn t -> {String.downcase(t.name), t} end)

    Enum.each(tag_names, fn name ->
      name_str = to_string(name) |> String.trim()

      if name_str != "" do
        case Map.get(existing_lower, String.downcase(name_str)) do
          nil ->
            # Create new tag
            case Tags.create_tag(%{name: name_str}) do
              {:ok, tag} -> Tags.add_tag_to_document(doc, tag)
              _ -> :ok
            end

          tag ->
            Tags.add_tag_to_document(doc, tag)
        end
      end
    end)

    doc
  end

  defp apply_tags(doc, _), do: doc

  defp apply_document_type(doc, nil), do: doc

  defp apply_document_type(doc, type_name) when is_binary(type_name) do
    type_name = String.trim(type_name)

    if type_name == "" do
      doc
    else
      all_types = DocumentTypes.list_types()
      matched = Enum.find(all_types, fn t -> String.downcase(t.name) == String.downcase(type_name) end)

      type =
        case matched do
          nil ->
            # Auto-create document type when LLM proposes a new one
            case DocumentTypes.create_type(%{name: type_name, description: type_name}) do
              {:ok, new_type} -> new_type
              {:error, _} -> nil
            end

          existing ->
            existing
        end

      case type do
        nil -> doc
        t ->
          {:ok, updated} = Documents.update_document(doc, %{document_type_id: t.id})
          updated
      end
    end
  end

  defp apply_document_type(doc, _), do: doc

  defp apply_correspondent(doc, nil), do: doc

  defp apply_correspondent(doc, corr_name) when is_binary(corr_name) do
    corr_name = String.trim(corr_name)

    if corr_name == "" do
      doc
    else
      all_corrs = Correspondents.list_correspondents()
      matched = Enum.find(all_corrs, fn c -> String.downcase(c.name) == String.downcase(corr_name) end)

      correspondent =
        case matched do
          nil ->
            # Auto-create correspondent when LLM suggests a new one
            case Correspondents.create_correspondent(%{name: corr_name}) do
              {:ok, new_corr} -> new_corr
              {:error, _} -> nil
            end

          existing ->
            existing
        end

      case correspondent do
        nil -> doc
        corr ->
          {:ok, updated} = Documents.update_document(doc, %{correspondent_id: corr.id})
          updated
      end
    end
  end

  defp apply_correspondent(doc, _), do: doc

  defp apply_involved_parties(doc, parties) when is_list(parties) and parties != [] do
    normalized =
      Enum.map(parties, fn party ->
        %{
          name: Map.get(party, :name, "") |> to_string(),
          role: Map.get(party, :role, "other") |> to_string(),
          document_id: doc.id
        }
      end)
      |> Enum.reject(&(&1.name == ""))

    if normalized != [] do
      InvolvedParties.replace_parties_for_document(doc.id, normalized)
    end

    doc
  end

  defp apply_involved_parties(doc, _), do: doc
end
