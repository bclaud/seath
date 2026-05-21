defmodule Seath.LLM.Classify do
  @moduledoc """
  Multi-step document classification using separate LLM calls per field.

  Instead of one-shot JSON classification, this module makes dedicated
  LLM calls for each classification dimension (metadata, tags, correspondent,
  involved parties). This follows the paperless-gpt approach where each
  field gets its own focused prompt, producing better results than a
  single monolithic prompt.

  Each step uses `Seath.LLM.chat/2` internally, delegating to the
  configured LLM provider.
  """

  @doc """
  Classifies a document by making separate LLM calls for each field.

  Returns a map with:
    - `:title` — concise document title
    - `:document_type` — best matching type or nil
    - `:tags` — list of relevant tag names
    - `:confidence` — overall confidence score (0.0-1.0)
    - `:correspondent` — suggested correspondent name or nil
    - `:involved_parties` — list of `%{name: String.t(), role: String.t()}` maps

  On error, returns `{:error, reason}` from the first failing step.
  """
  def classify_document(text, available_tags, available_types, available_correspondents \\ []) do
    with {:ok, metadata} <- extract_metadata(text, available_types),
         {:ok, tags} <- extract_tags(text, metadata.title, available_tags),
         {:ok, correspondent} <-
           extract_correspondent(text, metadata.title, available_correspondents),
         {:ok, involved_parties} <- extract_involved_parties(text) do
      {:ok,
       %{
         title: metadata.title,
         document_type: metadata.document_type,
         tags: tags,
         confidence: metadata.confidence,
         correspondent: correspondent,
         involved_parties: involved_parties
       }}
    end
  end

  @doc """
  Step 1: Extract metadata (title, document_type, confidence).

  Sends the document text to the LLM and asks for title, document_type
  (from the available types list), and confidence score.
  """
  def extract_metadata(text, available_types) do
    types_list = Enum.join(available_types, ", ")

    types_xml =
      if types_list != "",
        do: "<available_document_types>\n#{types_list}\n</available_document_types>\n\n",
        else: ""

    prompt = """
    Analyze the following document and extract metadata.

    #{types_xml}<content>
    #{String.slice(text, 0, 4000)}
    </content>

    Respond with ONLY a JSON object:
    {
      "title": "concise title max 80 chars",
      "document_type": "best match from list or null",
      "confidence": 0.0-1.0
    }
    """

    case Seath.LLM.chat([%{role: "user", content: prompt}],
           system:
             "You are a document metadata extraction assistant. Respond only with valid JSON."
         ) do
      {:ok, response} ->
        parse_metadata(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Step 2: Extract tags.

  Makes a separate LLM call focused only on selecting the most relevant
  tags from the available list.
  """
  def extract_tags(text, title, available_tags) do
    tags_list = Enum.join(available_tags, ", ")

    prompt = """
    Select the most relevant tags for this document from the available list.

    <available_tags>
    #{tags_list}
    </available_tags>

    <title>#{title}</title>
    <content>#{String.slice(text, 0, 3000)}</content>

    Respond with ONLY a JSON array of tag names: ["tag1", "tag2"]
    Be very selective — only choose tags that clearly apply.
    """

    case Seath.LLM.chat([%{role: "user", content: prompt}],
           system:
             "You are a document tag suggestion assistant. Respond only with a valid JSON array of tag names."
         ) do
      {:ok, response} ->
        parse_tags(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Step 3: Suggest a correspondent.

  Makes a separate LLM call to suggest a correspondent (sender/recipient)
  for this document, matched against the available correspondents list.
  """
  def extract_correspondent(text, title, available_correspondents) do
    corr_list = Enum.join(available_correspondents, ", ")

    prompt = """
    Suggest a correspondent (sender/recipient) for this document.

    <available_correspondents>
    #{corr_list}
    </available_correspondents>

    <title>#{title}</title>
    <content>#{String.slice(text, 0, 2000)}</content>

    Respond with ONLY the correspondent name, or "Unknown" if unsure.
    """

    case Seath.LLM.chat([%{role: "user", content: prompt}],
           system:
             "You are a document correspondent suggestion assistant. Respond only with a single name."
         ) do
      {:ok, response} ->
        name = String.trim(response)
        name = String.trim_trailing(name, ".")

        if String.downcase(name) in ["unknown", "none", "n/a", ""] do
          {:ok, nil}
        else
          {:ok, name}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Step 4: Extract involved parties.

  Makes a separate LLM call to extract all named entities (people,
  companies, organizations) mentioned in the document.
  """
  def extract_involved_parties(text) do
    prompt = """
    Extract all named entities (people, companies, organizations) mentioned in this document.

    <content>#{String.slice(text, 0, 4000)}</content>

    Respond with ONLY a JSON array:
    [{"name": "Entity Name", "role": "sender|recipient|subject|other"}]
    If no entities are found, respond with an empty array [].
    """

    case Seath.LLM.chat([%{role: "user", content: prompt}],
           system:
             "You are a named entity extraction assistant. Respond only with a valid JSON array."
         ) do
      {:ok, response} ->
        parse_involved_parties(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Private helpers ---

  defp parse_metadata(response) do
    case extract_json(response) do
      {:ok, %{"title" => title} = result} ->
        {:ok,
         %{
           title: title,
           document_type: Map.get(result, "document_type"),
           confidence: Map.get(result, "confidence", 0.5)
         }}

      {:ok, _} ->
        {:error, :invalid_metadata_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_tags(response) do
    case extract_json(response) do
      {:ok, tags} when is_list(tags) ->
        {:ok, Enum.map(tags, &to_string/1)}

      {:ok, %{} = tag_map} ->
        # Handle case where LLM returns {"tag1": true, "tag2": false} format
        tags =
          tag_map
          |> Enum.filter(fn {_k, v} -> v in [true, "true", 1] end)
          |> Enum.map(fn {k, _v} -> to_string(k) end)

        {:ok, tags}

      {:error, _} ->
        # Fallback: try to extract from a list pattern in string
        case Regex.run(~r/\[[\s\S]*?\]/, response) do
          [list_str] ->
            case Jason.decode(list_str) do
              {:ok, tags} when is_list(tags) -> {:ok, Enum.map(tags, &to_string/1)}
              _ -> {:ok, []}
            end

          nil ->
            {:ok, []}
        end
    end
  end

  defp parse_involved_parties(response) do
    case extract_json(response) do
      {:ok, parties} when is_list(parties) ->
        normalized =
          Enum.map(parties, fn party ->
            %{
              name: to_string(Map.get(party, "name", "")),
              role: to_string(Map.get(party, "role", "other"))
            }
          end)
          |> Enum.reject(&(&1.name == ""))

        {:ok, normalized}

      {:ok, _} ->
        {:ok, []}

      {:error, _} ->
        # Try to extract JSON array from the response
        case Regex.run(~r/\[[\s\S]*?\]/, response) do
          [array_str] ->
            case Jason.decode(array_str) do
              {:ok, parties} when is_list(parties) ->
                normalized =
                  Enum.map(parties, fn party ->
                    %{
                      name: to_string(Map.get(party, "name", "")),
                      role: to_string(Map.get(party, "role", "other"))
                    }
                  end)
                  |> Enum.reject(&(&1.name == ""))

                {:ok, normalized}

              _ ->
                {:ok, []}
            end

          nil ->
            {:ok, []}
        end
    end
  end

  defp extract_json(response) do
    trimmed = String.trim(response)

    # Try direct parse first
    case Jason.decode(trimmed) do
      {:ok, _} = ok ->
        ok

      {:error, _} ->
        # Try to extract JSON object or array using regex
        case Regex.run(~r/(\{[\s\S]*\}|\[[\s\S]*\])/, trimmed) do
          [json_str] ->
            Jason.decode(json_str)

          nil ->
            {:error, :no_json_found}
        end
    end
  end
end
