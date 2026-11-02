defmodule Seath.LLM.Ollama do
  @moduledoc """
  Ollama LLM provider.

  Uses an Ollama chat model (default: llama3.2) to classify document text,
  generate embeddings, and provide conversational chat responses.
  Requires a running Ollama instance.
  Configure via `OLLAMA_BASE_URL` and `OLLAMA_LLM_MODEL` environment
  variables or equivalent config entries.
  """
  @behaviour Seath.LLM.Provider

  @doc false
  def config do
    base_url =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:model) ||
        System.get_env("OLLAMA_LLM_MODEL", "gemma4")

    {base_url, model}
  end

  @doc false
  def vision_config do
    base_url =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:vision_model) ||
        System.get_env("OLLAMA_VISION_MODEL", "minicpm-v")

    {base_url, model}
  end

  @doc false
  def embed_config do
    base_url =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    embed_model =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:embed_model) ||
        System.get_env("OLLAMA_EMBED_MODEL", "bge-m3")

    {base_url, embed_model}
  end

  @impl true
  def classify(text, available_tags, available_types, opts \\ []) do
    {base_url, model} = config()
    do_classify(text, available_tags, available_types, opts, base_url, model)
  end

  defp do_classify(text, available_tags, available_types, opts, base_url, model) do
    language = Application.get_env(:seath, :document_language, "Portuguese")
    tags_list = Enum.join(available_tags, ", ")
    types_list = Enum.join(available_types, ", ")

    similar_context =
      case Keyword.get(opts, :similar_documents) do
        nil ->
          ""

        docs when is_list(docs) and docs != [] ->
          doc_blocks =
            Enum.map(docs, fn d ->
              doc = d.document || %{}

              tags_str =
                (doc.tags || [])
                |> Enum.map(& &1.name)
                |> Enum.join(", ")

              type_name = (doc.document_type && doc.document_type.name) || ""
              corr_name = (doc.correspondent && doc.correspondent.name) || ""

              """
              <document>
                <title>#{doc.title || ""}</title>
                <type>#{type_name}</type>
                <tags>#{tags_str}</tags>
                <correspondent>#{corr_name}</correspondent>
              </document>
              """
            end)

          "\n<similar_documents>\n#{Enum.join(doc_blocks, "\n")}\n</similar_documents>\n"

        _ ->
          ""
      end

    prompt = """
    I will provide you with the content of a document that has been read by OCR (so it may contain errors).
    Your task is to classify this document. The content is likely in #{language}.
    #{similar_context}
    <available_document_types>
    #{types_list}
    </available_document_types>

    <available_tags>
    #{tags_list}
    </available_tags>

    <content>
    #{text}
    </content>

    Respond with ONLY a JSON object with these fields:
    {
      "title": "a concise, descriptive title for this document (max 80 chars, in the document's language)",
      "document_type": "the single best matching type from <available_document_types>, or null if none match. Be sure to match: invoices/notas fiscais → invoice, emails → email, contracts → contract, etc.",
      "tags": ["REQUIRED: propose 2-5 tags. Start with best matches from <available_tags>, but feel free to suggest NEW tags if none fit perfectly. More tags = better retrieval. Include the most specific tags possible."],
      "correspondent": "the main sender or issuing company/person of this document, or null if unclear. Use a short, clean name without legal suffixes like Ltda, S.A., GmbH",
      "involved_parties": [{"name": "Entity Name", "role": "sender or recipient or subject or other"}]
    }
    """

    temperature = Keyword.get(opts, :temperature, 0.0)

    body = %{
      model: model,
      stream: false,
      options: %{temperature: temperature, num_ctx: 16384},
      messages: [%{role: "user", content: prompt}],
      format: classification_schema(available_types)
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        parse_classification(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def think(text, opts \\ []) do
    {base_url, model} = config()
    do_think(text, opts, base_url, model)
  end

  defp do_think(text, opts, base_url, model) do
    language = Application.get_env(:seath, :document_language, "Portuguese")
    temperature = Keyword.get(opts, :temperature, 0.0)

    prompt = """
    You are analyzing a document that was OCR-scanned (may contain errors).
    The document is likely in #{language}.

    Carefully read the document text and describe what you see.
    Extract key information in a structured way.

    <content>
    #{text}
    </content>

    Respond with ONLY a JSON object with these fields:
    {
      "reasoning": "A paragraph describing what this document is, who sent it, what it's about, and any important context you notice. Think step by step.",
      "extracted_entities": ["Full company names, person names, organizations mentioned"],
      "extracted_amounts": ["All monetary amounts, tax amounts, totals found"],
      "extracted_dates": ["All dates found in any format"],
      "summary": "A one-sentence summary of what this document is"
    }

    Be thorough in your reasoning. Note any ambiguities or unclear parts.
    """

    body = %{
      model: model,
      stream: false,
      options: %{temperature: temperature, num_ctx: 16384},
      messages: [%{role: "user", content: prompt}],
      format: thinking_schema()
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => message}}} ->
        content = Map.get(message, "content", "")
        native_thinking = Map.get(message, "thinking", "")
        parse_thinking(content, native_thinking)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def classify_from_reasoning(thinking, text, available_tags, available_types, opts \\ []) do
    {base_url, model} = config()

    do_classify_from_reasoning(
      thinking,
      text,
      available_tags,
      available_types,
      opts,
      base_url,
      model
    )
  end

  defp do_classify_from_reasoning(
         thinking,
         text,
         available_tags,
         available_types,
         opts,
         base_url,
         model
       ) do
    language = Application.get_env(:seath, :document_language, "Portuguese")
    tags_list = Enum.join(available_tags, ", ")
    types_list = Enum.join(available_types, ", ")
    temperature = Keyword.get(opts, :temperature, 0.0)
    retry_hint = Keyword.get(opts, :retry_hint, "")

    similar_context =
      case Keyword.get(opts, :similar_documents) do
        nil ->
          ""

        docs when is_list(docs) and docs != [] ->
          doc_blocks =
            Enum.map(docs, fn d ->
              doc = d.document || %{}
              tags_str = (doc.tags || []) |> Enum.map(& &1.name) |> Enum.join(", ")
              type_name = (doc.document_type && doc.document_type.name) || ""
              corr_name = (doc.correspondent && doc.correspondent.name) || ""

              """
              <document>
                <title>#{doc.title || ""}</title>
                <type>#{type_name}</type>
                <tags>#{tags_str}</tags>
                <correspondent>#{corr_name}</correspondent>
              </document>
              """
            end)

          "\n<similar_documents>\n#{Enum.join(doc_blocks, "\n")}\n</similar_documents>\n"

        _ ->
          ""
      end

    prompt = """
    I will provide you with the reasoning and extracted entities from a document analysis,
    along with the original OCR text. Use this to classify the document. The document is likely in #{language}.
    #{if retry_hint != "", do: "\nIMPORTANT: #{retry_hint}\n", else: ""}#{similar_context}
    <available_document_types>
    #{types_list}
    </available_document_types>

    <available_tags>
    #{tags_list}
    </available_tags>

    <document_analysis>
    <reasoning>#{thinking.reasoning}</reasoning>
    <extracted_entities>#{Enum.join(thinking.extracted_entities, ", ")}</extracted_entities>
    <extracted_amounts>#{Enum.join(thinking.extracted_amounts, ", ")}</extracted_amounts>
    <extracted_dates>#{Enum.join(thinking.extracted_dates, ", ")}</extracted_dates>
    <summary>#{thinking.summary}</summary>
    </document_analysis>

    <original_content>
    #{text}
    </original_content>

    Respond with ONLY a JSON object with these fields:
    {
      "title": "a concise, descriptive title for this document (max 80 chars, in the document's language)",
      "document_type": "the single best matching type from <available_document_types>, or null if none match. Be sure to match: invoices/faturas/contas/boletos/notas fiscais → invoice, emails → email, contracts → contract, receipts/comprovantes → receipt, etc.",
      "tags": ["REQUIRED: propose 2-5 tags. Start with best matches from <available_tags>, but feel free to suggest NEW tags if none fit perfectly. More tags = better retrieval. Include the most specific tags possible."],
      "correspondent": "the main sender or issuing company/person of this document, or null if unclear. Use a short, clean name without legal suffixes like Ltda, S.A., GmbH",
      "involved_parties": [{"name": "Entity Name", "role": "sender or recipient or subject or other"}],
      "type_confidence": 0.95,
      "needs_human_review": false,
      "is_actionable": true
    }
    """

    body = %{
      model: model,
      stream: false,
      options: %{temperature: temperature, num_ctx: 16384},
      messages: [%{role: "user", content: prompt}],
      format: classification_schema(available_types)
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        parse_classification(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def verify(classification, text) do
    do_verify(classification, text)
  end

  defp do_verify(classification, text) do
    text_norm = normalize_for_grounding(text)
    flagged = []
    verified = []

    # 1. Normalized token grounding for correspondent
    {verified, flagged} =
      if correspondent = Map.get(classification, :correspondent) do
        if grounded_in_text?(correspondent, text_norm) do
          {verified ++ ["correspondent"], flagged}
        else
          {verified,
           flagged ++
             [
               %{
                 field: "correspondent",
                 reason: "Name '#{correspondent}' not found in document text"
               }
             ]}
        end
      else
        {verified, flagged}
      end

    # 2. Normalized token grounding for involved parties
    {verified, flagged} =
      case Map.get(classification, :involved_parties, []) do
        parties when is_list(parties) and parties != [] ->
          Enum.reduce(parties, {verified, flagged}, fn party, {v, f} ->
            name = Map.get(party, :name, "") |> to_string()

            if name != "" and grounded_in_text?(name, text_norm) do
              {v ++ ["involved_party:#{name}"], f}
            else
              {v,
               f ++
                 [
                   %{
                     field: "involved_party",
                     reason: "Party '#{name}' not found in document text"
                   }
                 ]}
            end
          end)

        _ ->
          {verified, flagged}
      end

    # 3. Document type & JEV-like discriminative verification
    {verified, flagged} =
      if _type = Map.get(classification, :document_type) do
        {verified ++ ["document_type"], flagged}
      else
        {verified, flagged}
      end

    # 4. Check JEV-like decision flags (needs_human_review / type_confidence)
    flagged =
      if Map.get(classification, :needs_human_review) == true do
        flagged ++
          [
            %{
              field: "jev_decision",
              reason: "Model flagged document as ambiguous or requiring human review"
            }
          ]
      else
        flagged
      end

    # 5. Run System-1 JEV-like discriminative check if Ollama is reachable
    {verified, flagged} = maybe_run_jev_verify(classification, text, verified, flagged)

    passed? = flagged == []

    {:ok, %{passed: passed?, verified_fields: Enum.uniq(verified), flagged_fields: flagged}}
  end

  defp maybe_run_jev_verify(classification, text, verified, flagged) do
    {base_url, model} = config()
    correspondent = Map.get(classification, :correspondent)
    doc_type = Map.get(classification, :document_type)

    if is_nil(correspondent) and is_nil(doc_type) do
      {verified, flagged}
    else
      snippet = String.slice(text, 0, 4000)

      prompt = """
      Evaluate whether the proposed classification accurately matches the document text.
      Answer strictly as a discriminative judge:
      - correspondent_verified: true if '#{correspondent || "none"}' is genuinely the sender/issuer or main entity of this document (not a random footer mention or hallucination).
      - type_verified: true if '#{doc_type || "none"}' is an accurate category for this document.
      - confidence_score: calibrated probability from 0.0 to 1.0 that this classification is completely accurate.

      <document_text>
      #{snippet}
      </document_text>
      """

      body = %{
        model: model,
        stream: false,
        think: false,
        options: %{temperature: 0.0, num_ctx: 8192},
        format: %{
          type: "object",
          properties: %{
            correspondent_verified: %{type: "boolean"},
            type_verified: %{type: "boolean"},
            confidence_score: %{type: "number"}
          },
          required: ["correspondent_verified", "type_verified", "confidence_score"]
        },
        messages: [%{role: "user", content: prompt}]
      }

      case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 15_000) do
        {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
          case Jason.decode(content) do
            {:ok,
             %{
               "correspondent_verified" => corr_ok,
               "type_verified" => type_ok,
               "confidence_score" => score
             }} ->
              flagged =
                if correspondent && corr_ok == false do
                  flagged ++
                    [
                      %{
                        field: "correspondent",
                        reason:
                          "JEV discriminative check rejected '#{correspondent}' as document issuer"
                      }
                    ]
                else
                  flagged
                end

              flagged =
                if doc_type && type_ok == false do
                  flagged ++
                    [
                      %{
                        field: "document_type",
                        reason:
                          "JEV discriminative check rejected '#{doc_type}' as document type"
                      }
                    ]
                else
                  flagged
                end

              verified =
                if score >= 0.8 and corr_ok and type_ok do
                  verified ++ ["jev_calibrated"]
                else
                  verified
                end

              {verified, flagged}

            _ ->
              {verified, flagged}
          end

        _ ->
          # Gracefully keep deterministic verification if Ollama is offline/unreachable
          {verified, flagged}
      end
    end
  end

  @legal_suffix_regex ~r/\b(ltda|s\.?a\.?|s\/a|gmbh|ltd|inc|corp|srl|eirl|llc|me|epp|eireli|cia|companhia)\b\.?/i

  defp normalize_for_grounding(str) when is_binary(str) do
    str
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(@legal_suffix_regex, " ")
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
        # Check if all significant tokens (>= 3 chars) of the normalized entity appear in text
        tokens =
          entity_norm
          |> String.split(" ", trim: true)
          |> Enum.filter(&(String.length(&1) >= 3))

        tokens != [] and Enum.all?(tokens, &String.contains?(text_norm, &1))
    end
  end

  @target_embedding_dim 1536

  @impl true
  def embed(text) do
    {base_url, embed_model} = embed_config()

    body = %{
      model: embed_model,
      input: text
    }

    case Req.post("#{base_url}/api/embed", json: body, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _]}}} ->
        {:ok, align_embedding_dimension(embedding, @target_embedding_dim)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  # Isometrically aligns embedding vectors (e.g. 1024-dim bge-m3 or 768-dim nomic-embed-text)
  # to 1536 dimensions via zero-padding (which preserves exact cosine similarity & L2 norm)
  # or L2-normalized truncation if > 1536.
  defp align_embedding_dimension(vec, target_dim) when is_list(vec) do
    len = length(vec)

    cond do
      len == target_dim ->
        vec

      len < target_dim ->
        vec ++ List.duplicate(0.0, target_dim - len)

      len > target_dim ->
        truncated = Enum.take(vec, target_dim)
        norm = :math.sqrt(Enum.reduce(truncated, 0.0, fn x, acc -> acc + x * x end))

        if norm > 0.0 do
          Enum.map(truncated, &(&1 / norm))
        else
          truncated
        end
    end
  end

  @impl true
  def chat(messages, opts) do
    {base_url, model} = config()
    system_prompt = Keyword.get(opts, :system)
    messages = maybe_prepend_system(messages, system_prompt)

    body = %{
      model: model,
      stream: false,
      messages: messages
    }

    case Req.post("#{base_url}/api/chat", json: body) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def chat_with_tools(messages, tools, opts) do
    {base_url, model} = config()
    system_prompt = Keyword.get(opts, :system)
    messages = maybe_prepend_system(messages, system_prompt)

    body = %{
      model: model,
      stream: false,
      messages: messages,
      tools: tools
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => message}}} ->
        parse_tool_response(message)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def chat_stream(messages, opts, stream_to) do
    {base_url, model} = config()
    system_prompt = Keyword.get(opts, :system)
    messages = maybe_prepend_system(messages, system_prompt)

    body = %{model: model, stream: true, messages: messages}

    case Req.post("#{base_url}/api/chat", json: body, into: :self) do
      {:ok, %{status: 200} = resp} ->
        full_response = stream_ndjson(resp.body, stream_to)
        {:ok, full_response}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def ocr_vision(image_data, opts \\ []) do
    {base_url, model} = vision_config()
    prompt = Keyword.get(opts, :prompt)

    prompt =
      prompt ||
        "Just transcribe the text in this image and preserve the formatting and layout (high quality OCR). Be thorough and extract ALL text including numbers, amounts, dates, invoice numbers, tax IDs, and other structured data. Use markdown format but without a code block."

    body = %{
      model: model,
      stream: false,
      messages: [
        %{
          role: "user",
          content: prompt,
          images: [Base.encode64(image_data)]
        }
      ]
    }

    case Req.post("#{base_url}/api/chat", json: body, receive_timeout: 120_000) do
      {:ok, %{status: 200, body: %{"message" => %{"content" => content}}}} ->
        {:ok, String.trim(content)}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  defp maybe_prepend_system(messages, nil), do: messages
  defp maybe_prepend_system(messages, prompt), do: [%{role: "system", content: prompt} | messages]

  defp parse_tool_response(%{"tool_calls" => calls} = message) do
    content = Map.get(message, "content", "")

    tool_calls =
      Enum.map(calls, fn call ->
        %{
          id: call["id"] || "tool_#{:rand.uniform(999_999_999)}",
          type: "function",
          function: %{
            name: call["function"]["name"],
            arguments: call["function"]["arguments"]
          }
        }
      end)

    {:ok, %{content: content, tool_calls: tool_calls}}
  end

  defp parse_tool_response(%{"content" => content}) do
    {:ok, %{content: content, tool_calls: []}}
  end

  defp parse_tool_response(_other) do
    {:error, :invalid_response_format}
  end

  defp stream_ndjson(async_body, stream_to) do
    {token_list, _buffer} =
      Enum.reduce(async_body, {[], ""}, fn chunk, {tokens, buffer} ->
        full = buffer <> chunk
        lines = String.split(full, "\n")

        {complete_lines, new_buffer} =
          case List.pop_at(lines, -1) do
            {"", rest} -> {rest, ""}
            {last, []} -> {[], last}
            {last, rest} -> {rest, last}
          end

        new_tokens =
          Enum.flat_map(complete_lines, fn line ->
            case Jason.decode(line) do
              {:ok, %{"message" => %{"content" => token}, "done" => false}}
              when token != "" ->
                send(stream_to, {:stream_token, token})
                [token]

              {:ok, %{"done" => true}} ->
                []

              _ ->
                []
            end
          end)

        {tokens ++ new_tokens, new_buffer}
      end)

    Enum.join(token_list)
  end

  defp classification_schema(available_types) do
    doc_type_schema =
      case available_types do
        types when is_list(types) and types != [] ->
          %{enum: Enum.uniq(types) ++ [nil]}

        _ ->
          %{type: ["string", "null"]}
      end

    %{
      type: "object",
      properties: %{
        title: %{type: "string"},
        document_type: doc_type_schema,
        tags: %{type: "array", items: %{type: "string"}},
        correspondent: %{type: ["string", "null"]},
        involved_parties: %{
          type: "array",
          items: %{
            type: "object",
            properties: %{
              name: %{type: "string"},
              role: %{enum: ["sender", "recipient", "subject", "other"]}
            },
            required: ["name", "role"]
          }
        },
        type_confidence: %{type: "number"},
        needs_human_review: %{type: "boolean"},
        is_actionable: %{type: "boolean"}
      },
      required: [
        "title",
        "document_type",
        "tags",
        "correspondent",
        "involved_parties",
        "type_confidence",
        "needs_human_review",
        "is_actionable"
      ]
    }
  end

  defp thinking_schema do
    %{
      type: "object",
      properties: %{
        reasoning: %{type: "string"},
        extracted_entities: %{type: "array", items: %{type: "string"}},
        extracted_amounts: %{type: "array", items: %{type: "string"}},
        extracted_dates: %{type: "array", items: %{type: "string"}},
        summary: %{type: "string"}
      },
      required: [
        "reasoning",
        "extracted_entities",
        "extracted_amounts",
        "extracted_dates",
        "summary"
      ]
    }
  end

  defp parse_classification(content) do
    case Jason.decode(content) do
      {:ok, %{"title" => title} = result} ->
        {:ok, build_result(title, result)}

      {:ok, _} ->
        {:error, :invalid_response_format}

      {:error, _} ->
        # Try to extract JSON from the response if it's wrapped in markdown or extra text
        case Regex.run(~r/\{[\s\S]*\}/, content) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, %{"title" => title} = result} ->
                {:ok, build_result(title, result)}

              _ ->
                {:error, :invalid_response_format}
            end

          nil ->
            {:error, :invalid_response_format}
        end
    end
  end

  defp parse_thinking(content, native_thinking) do
    case Jason.decode(content) do
      {:ok, result} ->
        {:ok, build_thinking_result(result, native_thinking)}

      {:error, _} ->
        case Regex.run(~r/\{[\s\S]*\}/, content) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, result} ->
                {:ok, build_thinking_result(result, native_thinking)}

              _ ->
                {:error, :invalid_response_format}
            end

          nil ->
            {:error, :invalid_response_format}
        end
    end
  end

  defp build_thinking_result(result, native_thinking) do
    json_reasoning = Map.get(result, "reasoning", "")

    reasoning =
      cond do
        json_reasoning != "" and native_thinking != "" ->
          "#{json_reasoning}\n\n[Model Chain-of-Thought]\n#{native_thinking}"

        json_reasoning != "" ->
          json_reasoning

        true ->
          native_thinking
      end

    %{
      reasoning: reasoning,
      extracted_entities: Map.get(result, "extracted_entities", []),
      extracted_amounts: Map.get(result, "extracted_amounts", []),
      extracted_dates: Map.get(result, "extracted_dates", []),
      summary: Map.get(result, "summary", "")
    }
  end

  defp build_result(title, result) do
    involved_parties =
      case Map.get(result, "involved_parties", []) do
        parties when is_list(parties) ->
          Enum.map(parties, fn p ->
            %{
              name: to_string(Map.get(p, "name", "")),
              role: to_string(Map.get(p, "role", "other"))
            }
          end)
          |> Enum.reject(&(&1.name == ""))

        _ ->
          []
      end

    correspondent =
      case Map.get(result, "correspondent") do
        nil -> nil
        name when is_binary(name) and name != "" -> String.trim(name)
        _ -> nil
      end

    %{
      title: title,
      document_type: Map.get(result, "document_type"),
      tags: Map.get(result, "tags", []),
      correspondent: correspondent,
      involved_parties: involved_parties,
      type_confidence: Map.get(result, "type_confidence"),
      needs_human_review: Map.get(result, "needs_human_review", false),
      is_actionable: Map.get(result, "is_actionable", false)
    }
  end
end
