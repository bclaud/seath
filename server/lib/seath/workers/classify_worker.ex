defmodule Seath.Workers.ClassifyWorker do
  @moduledoc """
  Oban worker that classifies a document using multi-step LLM classification.

  Fetches the document, validates OCR text is present, runs multi-step
  classification (metadata, tags, correspondent, involved parties),
  applies the results, and transitions the document to awaiting_review.

  If the multi-step classification fails, falls back to the legacy
  one-shot classification for backward compatibility.

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
         tags <- Tags.list_tags() |> Enum.map(& &1.name),
         types <- DocumentTypes.list_types() |> Enum.map(& &1.name),
         correspondents <- Correspondents.list_correspondents() |> Enum.map(& &1.name),
         {:ok, result} <- classify(text, tags, types, correspondents),
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

  defp classify(text, tags, types, correspondents) do
    case Seath.LLM.Classify.classify_document(text, tags, types, correspondents) do
      {:ok, result} ->
        {:ok, result}

      {:error, _reason} ->
        Logger.warning("Multi-step classification failed, falling back to one-shot classify")
        fallback_classify(text, tags, types)
    end
  end

  defp fallback_classify(text, tags, types) do
    case Seath.LLM.classify(text, tags, types) do
      {:ok, result} ->
        {:ok,
         %{
           title: result.title,
           document_type: result.document_type,
           tags: result.tags,
           confidence: result.confidence,
           correspondent: nil,
           involved_parties: []
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_classification(doc, result) do
    # Update document title and confidence
    {:ok, doc} =
      Documents.update_document(doc, %{title: result.title, confidence: result.confidence})

    # Apply tags — validate against existing tags, create if needed
    doc = apply_tags(doc, result.tags)

    # Apply document type — validate against existing types
    doc = apply_document_type(doc, result.document_type)

    # Apply correspondent — match against existing correspondents, don't create new ones
    doc = apply_correspondent(doc, result.correspondent)

    # Apply involved parties — create entries for extracted entities
    apply_involved_parties(doc, result.involved_parties)

    # Transition to awaiting_review
    Documents.transition_status(doc, "awaiting_review")
  end

  defp apply_tags(doc, tag_names) when is_list(tag_names) do
    validated_tags = validate_tag_names(tag_names)

    Enum.each(validated_tags, fn tag_name ->
      case Tags.get_tag_by_name(tag_name) do
        nil ->
          {:ok, tag} = Tags.create_tag(%{name: tag_name})
          Tags.add_tag_to_document(doc, tag)

        tag ->
          Tags.add_tag_to_document(doc, tag)
      end
    end)

    doc
  end

  defp apply_tags(doc, _), do: doc

  defp apply_document_type(doc, nil), do: doc

  defp apply_document_type(doc, type_name) do
    case DocumentTypes.get_type_by_name(type_name) do
      nil ->
        # Also try case-insensitive match
        matched_type = find_type_case_insensitive(type_name)

        case matched_type do
          nil ->
            doc

          type ->
            {:ok, updated} = Documents.update_document(doc, %{document_type_id: type.id})
            updated
        end

      type ->
        {:ok, updated} = Documents.update_document(doc, %{document_type_id: type.id})
        updated
    end
  end

  defp apply_correspondent(doc, nil), do: doc

  defp apply_correspondent(doc, corr_name) do
    # Try to find an existing correspondent (case-insensitive)
    existing = find_correspondent_case_insensitive(corr_name)

    case existing do
      nil ->
        # Don't create new correspondents automatically — user can set manually
        doc

      correspondent ->
        {:ok, updated} = Documents.update_document(doc, %{correspondent_id: correspondent.id})
        updated
    end
  end

  defp apply_involved_parties(doc, parties) when is_list(parties) and parties != [] do
    normalized_parties =
      Enum.map(parties, fn party ->
        %{name: party.name, role: party.role, document_id: doc.id}
      end)

    InvolvedParties.replace_parties_for_document(doc.id, normalized_parties)
    doc
  end

  defp apply_involved_parties(_doc, _), do: :ok

  # --- Validation helpers ---

  defp validate_tag_names(tag_names) when is_list(tag_names) do
    all_tags = Tags.list_tags() |> Enum.map(&String.downcase(&1.name))
    all_tag_names = Tags.list_tags() |> Enum.map(& &1.name)

    Enum.flat_map(tag_names, fn name ->
      name_str = to_string(name)

      cond do
        Enum.member?(all_tag_names, name_str) ->
          [name_str]

        Enum.member?(all_tags, String.downcase(name_str)) ->
          # Case-insensitive match — return the original cased name
          idx = Enum.find_index(all_tags, &(&1 == String.downcase(name_str)))
          [Enum.at(all_tag_names, idx)]

        true ->
          # Allow creating new tags for unmatched names
          [name_str]
      end
    end)
  end

  defp validate_tag_names(_), do: []

  defp find_type_case_insensitive(name) do
    all_types = DocumentTypes.list_types()
    Enum.find(all_types, fn t -> String.downcase(t.name) == String.downcase(name) end)
  end

  defp find_correspondent_case_insensitive(name) do
    all_corrs = Correspondents.list_correspondents()
    Enum.find(all_corrs, fn c -> String.downcase(c.name) == String.downcase(name) end)
  end
end
