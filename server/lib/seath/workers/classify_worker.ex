defmodule Seath.Workers.ClassifyWorker do
  @moduledoc """
  Oban worker that classifies a document using the LLM via a multi-step pipeline:

  1. **Chunking** — splits long documents into manageable chunks with overlap
  2. **Think phase** — calls the LLM to reason about the document and extract entities
  3. **Merge phase** — combines extractions from multiple chunks
  4. **Classify phase** — uses extracted entities + reasoning to produce structured classification
  5. **Verification** — cross-checks classification against document text
  6. **Heuristic confidence** — computes confidence from verifiable signals
  7. **Auto-reclassification** — retries with different prompt if confidence is low
  8. **Application** — saves classification results to the document
  """
  use Oban.Worker, queue: :classify, max_attempts: 3

  alias Seath.Documents
  alias Seath.Tags
  alias Seath.DocumentTypes
  alias Seath.Correspondents
  alias Seath.InvolvedParties
  alias Seath.Retrieval
  require Logger

  # Chunking constants
  @max_direct_text 8_000
  @chunk_size 6_000
  @chunk_overlap 500
  @max_retries 2
  @high_confidence_threshold 0.7
  @low_confidence_threshold 0.4

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}} = job) do
    try do
      with {:ok, doc} <- fetch_document(id),
           {:ok, text} <- validate_ocr_text(doc) do
        attempt = Map.get(job.args, "classify_attempt", 0) + 1

        # Update attempt count on document
        {:ok, doc} = Documents.update_document(doc, %{classification_attempts: attempt})

        result = classify_with_pipeline(text, attempt)

        case result do
          {:ok,
           %{
             classification: classification,
             thinking: thinking,
             verification: verification,
             confidence: confidence
           }} ->
            # Apply classification to document
            {:ok, doc} =
              store_classification_data(doc, classification, thinking, verification, confidence)

            cond do
              confidence >= @high_confidence_threshold ->
                # Good enough — apply and transition to awaiting_review
                {:ok, _doc} = apply_classification(doc, classification)
                broadcast_update(doc.id, "awaiting_review")
                :ok

              attempt < @max_retries ->
                # Low confidence — retry with different parameters
                Logger.info(
                  "Classification confidence #{confidence} below threshold, retrying (attempt #{attempt})"
                )

                {:ok, _doc} = store_retry_hint(doc, thinking, verification)
                reclassify_with_retry(doc, attempt)

              confidence < @low_confidence_threshold ->
                # Still bad after max retries — apply with warning
                Logger.warning(
                  "Classification confidence #{confidence} too low after #{attempt} attempts, flagging for review"
                )

                {:ok, doc} =
                  Documents.update_document(doc, %{confidence: confidence, title: doc.title})

                {:ok, _doc} = apply_classification(doc, classification)
                broadcast_update(doc.id, "awaiting_review")
                :ok

              true ->
                # Acceptable after retry
                {:ok, _doc} = apply_classification(doc, classification)
                broadcast_update(doc.id, "awaiting_review")
                :ok
            end

          {:error, reason} ->
            handle_error(id, reason)
        end
      else
        {:error, reason} -> handle_error(id, reason)
      end
    rescue
      e ->
        msg = "Unexpected classification error: #{Exception.message(e)}"
        Logger.error(msg)
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        mark_error(id, msg)
        {:discard, :exception}
    end
  end

  # ============================================================================
  # Pipeline
  # ============================================================================

  defp classify_with_pipeline(text, attempt) do
    # Load available tags and types
    tags = Tags.list_tags()
    types = DocumentTypes.list_types()
    tag_names = Enum.map(tags, & &1.name)
    type_names = Enum.map(types, & &1.name)

    # Search for similar archived documents via semantic embeddings (with keyword fallback)
    similar_docs = find_similar_archived_documents(text)

    base_opts = if similar_docs != [], do: [similar_documents: similar_docs], else: []

    # Deterministic temperature on first pass; slight exploration only on retry
    base_opts =
      if attempt > 1 do
        Keyword.put(base_opts, :temperature, 0.2)
      else
        Keyword.put(base_opts, :temperature, 0.0)
      end

    # Phase 1: Chunk and think
    thinking_result = think_pipeline(text, base_opts)

    case thinking_result do
      {:ok, thinking} ->
        # Phase 2: Classify from reasoning
        retry_hint =
          if attempt > 1 do
            "Be very careful, the previous attempt had low confidence. Double-check your classification."
          else
            ""
          end

        opts_with_hint =
          if retry_hint != "" do
            Keyword.put(base_opts, :retry_hint, retry_hint)
          else
            base_opts
          end

        similar_docs_len = length(similar_docs)

        case Seath.LLM.classify_from_reasoning(
               thinking,
               text,
               tag_names,
               type_names,
               opts_with_hint
             ) do
          {:ok, classification} ->
            # Phase 3: Verify
            case Seath.LLM.verify(classification, text) do
              {:ok, verification} ->
                # Phase 4: Compute heuristic confidence
                confidence =
                  compute_confidence(text, classification, similar_docs_len, verification)

                {:ok,
                 %{
                   classification: classification,
                   thinking: thinking,
                   verification: verification,
                   confidence: confidence
                 }}

              {:error, reason} ->
                # If verification fails, still proceed with unverified flag
                Logger.warning("Verification failed: #{inspect(reason)}")
                confidence = compute_confidence(text, classification, similar_docs_len, nil)

                verification = %{
                  passed: false,
                  verified_fields: [],
                  flagged_fields: [%{field: "verification", reason: "Verification call failed"}]
                }

                {:ok,
                 %{
                   classification: classification,
                   thinking: thinking,
                   verification: verification,
                   confidence: confidence
                 }}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Thinking Pipeline (with chunking)
  # ============================================================================

  defp think_pipeline(text, opts) do
    chunks = chunk_text(text)

    if length(chunks) == 1 do
      # Single chunk — simple case
      case Seath.LLM.think(List.first(chunks), opts) do
        {:ok, thinking} -> {:ok, thinking}
        error -> error
      end
    else
      # Multiple chunks — think about each, then merge
      results =
        chunks
        |> Task.async_stream(
          fn chunk -> Seath.LLM.think(chunk, opts) end,
          timeout: 120_000,
          max_concurrency: 2
        )
        |> Enum.reduce_while([], fn
          {:ok, {:ok, result}}, acc -> {:cont, [result | acc]}
          {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
          {:exit, reason}, _acc -> {:halt, {:error, reason}}
        end)

      case results do
        {:error, reason} ->
          {:error, reason}

        thinking_results when is_list(thinking_results) ->
          {:ok, merge_thinking_results(thinking_results)}
      end
    end
  end

  # ============================================================================
  # Chunking
  # ============================================================================

  defp chunk_text(text) when byte_size(text) <= @max_direct_text, do: [text]

  defp chunk_text(text) do
    text
    |> split_into_chunks(@chunk_size, @chunk_overlap)
    |> Enum.reject(&(&1 == "" or &1 == nil))
  end

  defp split_into_chunks(text, chunk_size, _overlap) when byte_size(text) <= chunk_size do
    [text]
  end

  defp split_into_chunks(text, chunk_size, overlap) do
    # Split at sentence boundaries near the chunk size for cleaner breaks
    do_split_chunks(text, chunk_size, overlap, [])
  end

  defp do_split_chunks(text, _chunk_size, _overlap, acc)
       when byte_size(text) <= @max_direct_text do
    Enum.reverse([text | acc])
  end

  defp do_split_chunks(text, chunk_size, overlap, acc) do
    # Find a good break point near chunk_size bytes
    take = min(chunk_size, byte_size(text))
    break_at = find_break_point(text, take)

    # Use binary_part for byte-accurate slicing
    chunk_part = :binary.part(text, 0, break_at)
    remaining_start = max(0, break_at - overlap)
    remaining_len = byte_size(text) - remaining_start
    remaining = :binary.part(text, remaining_start, remaining_len)

    do_split_chunks(remaining, chunk_size, overlap, [chunk_part | acc])
  end

  defp find_break_point(text, max_size) do
    half = div(max_size, 2)
    # Only search within the first max_size bytes
    search_region = :binary.part(text, 0, max_size)

    # Find last occurrence of each candidate after the halfway point
    last_newline = find_last_substring(search_region, "\n")
    last_period = find_last_substring(search_region, ". ")

    candidates =
      [last_newline, last_period]
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&(&1 > half))

    case candidates do
      [] ->
        max_size

      _ ->
        pos = Enum.max(candidates)
        if last_newline && pos == last_newline, do: pos + 1, else: pos + 2
    end
  end

  defp find_last_substring(string, pattern) do
    # Scan for all occurrences and return the last one
    do_find_last(string, pattern, 0, nil)
  end

  defp do_find_last(string, pattern, offset, last_found) do
    remaining = byte_size(string) - offset

    if remaining <= 0 do
      last_found
    else
      case :binary.match(string, pattern, [{:scope, {offset, remaining}}]) do
        {pos, len} ->
          do_find_last(string, pattern, pos + len, pos)

        :nomatch ->
          last_found
      end
    end
  end

  # ============================================================================
  # Merging Thinking Results
  # ============================================================================

  defp merge_thinking_results(results) when is_list(results) do
    %{
      reasoning:
        results
        |> Enum.map(& &1.reasoning)
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n---\n\n"),
      extracted_entities:
        results
        |> Enum.flat_map(& &1.extracted_entities)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq(),
      extracted_amounts:
        results
        |> Enum.flat_map(& &1.extracted_amounts)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq(),
      extracted_dates:
        results
        |> Enum.flat_map(& &1.extracted_dates)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq(),
      summary:
        results
        |> List.first(%{})
        |> Map.get(:summary, "")
    }
  end

  defp merge_thinking_results(_),
    do: %{
      reasoning: "",
      extracted_entities: [],
      extracted_amounts: [],
      extracted_dates: [],
      summary: ""
    }

  # ============================================================================
  # Semantic Retrieval for Few-Shot Classification Grounding
  # ============================================================================

  defp find_similar_archived_documents(text) when is_binary(text) do
    snippet = String.slice(text, 0, 4_000)

    vector_docs =
      try do
        case Seath.LLM.embed(snippet) do
          {:ok, embedding} when is_list(embedding) ->
            Seath.Embeddings.similarity_search(embedding, limit: 3, min_score: 0.65)
            |> Enum.map(fn %{document: doc} = item ->
              preloaded = Seath.Repo.preload(doc, [:tags, :document_type, :correspondent])
              %{item | document: preloaded}
            end)

          _ ->
            []
        end
      rescue
        _ -> []
      end

    if vector_docs != [] do
      vector_docs
    else
      # Fallback: extract first meaningful short line for keyword search
      first_line =
        text
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.find("", &(String.length(&1) >= 4 and String.length(&1) <= 80))

      if first_line != "" do
        Retrieval.search(first_line,
          limit: 3,
          max_docs: 3,
          include_docs: true,
          status: "archived"
        )
      else
        []
      end
    end
  end

  defp find_similar_archived_documents(_), do: []

  # ============================================================================
  # Heuristic & JEV-like Calibrated Confidence Scoring (Item 4)
  # ============================================================================

  def compute_confidence(text, classification, similar_docs_count, verification) do
    text_norm = normalize_for_grounding(text)

    # 1. Type match score (0.0 - 0.3)
    type_match =
      if type = Map.get(classification, :document_type) do
        existing_types = DocumentTypes.list_types()
        type_lower = String.downcase(type)

        base_type_score =
          if Enum.any?(existing_types, fn t ->
               String.downcase(t.name) == type_lower or
                 String.downcase(t.name) |> String.starts_with?(type_lower) or
                 type_lower |> String.starts_with?(String.downcase(t.name))
             end) do
            0.3
          else
            0.15
          end

        case Map.get(classification, :type_confidence) do
          c when is_number(c) and c >= 0.0 and c <= 1.0 ->
            base_type_score * (0.5 + 0.5 * c)

          _ ->
            base_type_score
        end
      else
        0.1
      end

    # 2. Entity grounding score (0.0 - 0.25)
    entity_grounding =
      compute_entity_grounding(classification, text_norm)

    # 3. Context quality score (0.0 - 0.2) - more similar docs = better context
    context_quality = min(similar_docs_count / 3, 1.0) * 0.2

    # 4. Verification score (0.0 - 0.25, +0.05 bonus if JEV calibrated)
    verification_score =
      case verification do
        nil ->
          0.1

        %{passed: true, verified_fields: vf} when is_list(vf) ->
          if "jev_calibrated" in vf, do: 0.3, else: 0.25

        %{passed: true} ->
          0.25

        %{passed: false, flagged_fields: flagged} when is_list(flagged) ->
          # Penalize proportionally to flagged fields
          max(0.05, 0.25 - length(flagged) * 0.07)

        _ ->
          0.05
      end

    # 5. Internal consistency score (0.0 - 0.2)
    internal_consistency =
      compute_internal_consistency(classification)

    # 6. JEV-like needs_human_review penalty
    review_penalty =
      if Map.get(classification, :needs_human_review) == true, do: -0.15, else: 0.0

    scores = %{
      type_match: type_match,
      entity_grounding: entity_grounding,
      context_quality: context_quality,
      verification: verification_score,
      internal_consistency: internal_consistency,
      review_penalty: review_penalty
    }

    Map.values(scores) |> Enum.sum() |> max(0.0) |> min(1.0) |> Float.round(2)
  end

  defp compute_entity_grounding(classification, text_norm) do
    entities =
      ([Map.get(classification, :correspondent)] ++
         (Map.get(classification, :involved_parties, []) |> Enum.map(& &1.name)))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    case entities do
      [] ->
        0.15

      ents ->
        found = Enum.count(ents, fn ent -> grounded_in_text?(ent, text_norm) end)
        ratio = found / length(ents)
        ratio * 0.25
    end
  end

  @legal_suffixes ~r/\b(ltda|s\.?a\.?|s\/a|gmbh|ltd|inc|corp|srl|eirl|llc|co\b|company|limited|associação|fundacao|me|epp|eireli)\b\.?/i

  defp normalize_for_grounding(str) when is_binary(str) do
    str
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(@legal_suffixes, " ")
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_for_grounding(_), do: ""

  defp grounded_in_text?(entity_name, text_norm) do
    entity_norm = normalize_for_grounding(entity_name)

    cond do
      entity_norm == "" ->
        false

      String.contains?(text_norm, entity_norm) ->
        true

      true ->
        tokens =
          entity_norm
          |> String.split(" ", trim: true)
          |> Enum.filter(&(String.length(&1) >= 3))

        tokens != [] and Enum.all?(tokens, &String.contains?(text_norm, &1))
    end
  end

  defp compute_internal_consistency(classification) do
    correspondent = Map.get(classification, :correspondent)
    parties = Map.get(classification, :involved_parties, []) |> Enum.map(& &1.name)

    if correspondent && parties != [] do
      if Enum.any?(parties, fn p ->
           String.downcase(p) == String.downcase(correspondent)
         end) do
        0.2
      else
        0.1
      end
    else
      0.15
    end
  end

  # ============================================================================
  # Entity Normalization (Item 6)
  # ===========================================================================

  def normalize_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(@legal_suffixes, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_name(_), do: ""

  def find_existing_entity(name, existing_entities, name_accessor \\ & &1) do
    name_str = to_string(name) |> String.trim()
    find_entity_match(name_str, existing_entities, name_accessor)
  end

  defp find_entity_match(name_str, existing_entities, name_accessor) do
    # 1. Exact case-insensitive match
    if Enum.any?(existing_entities, fn e ->
         String.downcase(name_accessor.(e)) == String.downcase(name_str)
       end) do
      :exact_match
    else
      # 2. Normalized match
      normalized = normalize_name(name_str)

      if normalized != "" &&
           Enum.any?(existing_entities, fn e ->
             normalize_name(name_accessor.(e)) == normalized
           end) do
        :normalized_match
      else
        # 3. Levenshtein similarity
        if Enum.any?(existing_entities, fn e ->
             existing_name = name_accessor.(e)

             String.length(existing_name) > 3 &&
               String.length(name_str) > 3 &&
               levenshtein_similarity(
                 String.downcase(existing_name),
                 String.downcase(name_str)
               ) >= 0.8
           end) do
          :similar_match
        else
          :new
        end
      end
    end
  end

  defp levenshtein_similarity(s1, s2) do
    len1 = String.length(s1)
    len2 = String.length(s2)

    max_len = max(len1, len2)
    if max_len == 0, do: 1.0

    distance = levenshtein_distance(s1, s2)
    1.0 - distance / max_len
  end

  defp levenshtein_distance(s1, s2) do
    len1 = String.length(s1)
    len2 = String.length(s2)

    prev_row = Enum.to_list(0..len2)

    final_row =
      Enum.reduce(1..len1, prev_row, fn i, prev ->
        curr = List.duplicate(0, len2 + 1)
        curr = List.replace_at(curr, 0, i)
        s1_char = String.at(s1, i - 1)

        {new_row, _} =
          Enum.reduce(1..len2, {curr, 0}, fn j, {row, _prev_val} ->
            cost = if s1_char == String.at(s2, j - 1), do: 0, else: 1

            val =
              [Enum.at(row, j - 1) + 1, Enum.at(prev, j) + 1, Enum.at(prev, j - 1) + cost]
              |> Enum.min()

            {List.replace_at(row, j, val), val}
          end)

        new_row
      end)

    Enum.at(final_row, len2)
  end

  # ============================================================================
  # Retry Logic (Item 7)
  # ===========================================================================

  defp reclassify_with_retry(doc, attempt) do
    # Insert a new classification job for the same document
    %{document_id: doc.id, classify_attempt: attempt}
    |> __MODULE__.new(schedule_in: 0)
    |> Oban.insert()

    # Don't discard — let the new job handle it
    {:discard, :retrying}
  end

  defp store_retry_hint(doc, thinking, verification) do
    # Store the previous reasoning so the retry can reference it
    hint = %{
      previous_thinking: thinking,
      previous_verification: verification,
      retry_reason: "Low heuristic confidence"
    }

    Documents.update_document(doc, %{llm_reasoning: Jason.encode!(hint)})
  end

  # ============================================================================
  # Data Storage
  # ===========================================================================

  defp store_classification_data(doc, classification, thinking, verification, confidence) do
    jev_meta = %{
      type_confidence: Map.get(classification, :type_confidence),
      needs_human_review: Map.get(classification, :needs_human_review, false),
      is_actionable: Map.get(classification, :is_actionable, false)
    }

    enriched_verification =
      (verification || %{})
      |> Map.put(:is_actionable, jev_meta.is_actionable)
      |> Map.put(:needs_human_review, jev_meta.needs_human_review)
      |> Map.put(:type_confidence, jev_meta.type_confidence)

    attrs = %{
      llm_reasoning:
        Jason.encode!(%{
          thinking: thinking,
          verification: enriched_verification,
          classification: jev_meta
        }),
      verification_data: enriched_verification,
      confidence: confidence
    }

    Documents.update_document(doc, attrs)
  end

  # ============================================================================
  # Classification Application (with entity normalization)
  # ===========================================================================

  defp apply_classification(doc, result) do
    # Update document title (confidence already set in store_classification_data)
    {:ok, doc} = Documents.update_document(doc, %{title: result.title})

    # Apply document type with normalization
    doc = apply_document_type(doc, result.document_type)

    # Apply tags with normalization
    doc = apply_tags(doc, result.tags)

    # Apply correspondent with normalization
    doc = apply_correspondent(doc, Map.get(result, :correspondent))

    # Apply involved parties with normalization
    apply_involved_parties(doc, Map.get(result, :involved_parties, []))

    # Transition to awaiting_review
    Documents.transition_status(doc, "awaiting_review")
  end

  # --- Tags (with normalization) ---

  defp apply_tags(doc, tag_names) when is_list(tag_names) do
    existing_tags = Tags.list_tags()

    Enum.each(tag_names, fn name ->
      name_str = to_string(name) |> String.trim()

      if name_str != "" do
        match_type = find_existing_entity(name_str, existing_tags, & &1.name)

        tag =
          case match_type do
            :new ->
              case Tags.create_tag(%{name: name_str}) do
                {:ok, tag} -> tag
                _ -> nil
              end

            _ ->
              # Find the matching tag by normalized name
              find_best_entity_match(name_str, existing_tags, & &1.name)
          end

        if tag do
          Tags.add_tag_to_document(doc, tag)
        end
      end
    end)

    doc
  end

  defp apply_tags(doc, _), do: doc

  # --- Document Type (with normalization) ---

  defp apply_document_type(doc, nil), do: doc

  defp apply_document_type(doc, type_name) when is_binary(type_name) do
    type_name = String.trim(type_name)

    if type_name == "" do
      doc
    else
      all_types = DocumentTypes.list_types()
      match_type = find_existing_entity(type_name, all_types, & &1.name)

      type =
        case match_type do
          :new ->
            case DocumentTypes.create_type(%{name: type_name, description: type_name}) do
              {:ok, new_type} -> new_type
              {:error, _} -> nil
            end

          _ ->
            find_best_entity_match(type_name, all_types, & &1.name)
        end

      case type do
        nil ->
          doc

        t ->
          {:ok, updated} = Documents.update_document(doc, %{document_type_id: t.id})
          updated
      end
    end
  end

  defp apply_document_type(doc, _), do: doc

  # --- Correspondent (with normalization) ---

  defp apply_correspondent(doc, nil), do: doc

  defp apply_correspondent(doc, corr_name) when is_binary(corr_name) do
    corr_name = String.trim(corr_name)

    if corr_name == "" do
      doc
    else
      all_corrs = Correspondents.list_correspondents()
      match_type = find_existing_entity(corr_name, all_corrs, & &1.name)

      correspondent =
        case match_type do
          :new ->
            case Correspondents.create_correspondent(%{name: corr_name}) do
              {:ok, new_corr} -> new_corr
              {:error, _} -> nil
            end

          _ ->
            find_best_entity_match(corr_name, all_corrs, & &1.name)
        end

      case correspondent do
        nil ->
          doc

        corr ->
          {:ok, updated} = Documents.update_document(doc, %{correspondent_id: corr.id})
          updated
      end
    end
  end

  defp apply_correspondent(doc, _), do: doc

  # --- Involved Parties ---

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

  # ============================================================================
  # Entity Matching Helpers
  # ===========================================================================

  defp find_best_entity_match(name, entities, name_accessor) do
    name_str = to_string(name) |> String.trim()
    normalized = normalize_name(name_str)

    # Try exact first
    exact =
      Enum.find(entities, fn e ->
        String.downcase(name_accessor.(e)) == String.downcase(name_str)
      end)

    if exact do
      exact
    else
      # Try normalized
      normalized_match =
        Enum.find(entities, fn e ->
          normalize_name(name_accessor.(e)) == normalized
        end)

      if normalized_match do
        normalized_match
      else
        # Try Levenshtein
        Enum.find(entities, fn e ->
          existing_name = name_accessor.(e)

          String.length(existing_name) > 3 &&
            String.length(name_str) > 3 &&
            levenshtein_similarity(String.downcase(existing_name), String.downcase(name_str)) >=
              0.8
        end)
      end
    end
  end

  # ============================================================================
  # Error Handling
  # ===========================================================================

  defp handle_error(id, reason) do
    case reason do
      :not_configured ->
        msg = "No LLM provider configured. Go to Settings to configure one."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :not_configured}

      :connection_refused ->
        msg = "LLM provider unreachable. Check that Ollama is running."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :connection_refused}

      :no_ocr_text ->
        msg = "Document has no OCR text. OCR may have failed."
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, :no_ocr_text}

      :not_found ->
        msg = "Document not found."
        Logger.error(msg)
        {:discard, :not_found}

      reason ->
        msg = "Classification error: #{inspect(reason)}"
        Logger.error(msg)
        mark_error(id, msg)
        {:discard, reason}
    end
  end

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

  defp broadcast_update(document_id, status) do
    Phoenix.PubSub.broadcast(
      Seath.PubSub,
      "documents",
      {:document_updated, %{id: document_id, status: status}}
    )
  end
end
