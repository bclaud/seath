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
        System.get_env("OLLAMA_LLM_MODEL", "llama3.2")

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
        System.get_env("OLLAMA_VISION_MODEL", "llama3.2-vision")

    {base_url, model}
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
    #{String.slice(text, 0, 4000)}
    </content>

    Respond with ONLY a JSON object with these fields:
    {
      "title": "a concise, descriptive title for this document (max 80 chars, in the document's language)",
      "document_type": "the single best matching type from <available_document_types>, or null if none match. Be sure to match: invoices/notas fiscais → invoice, emails → email, contracts → contract, etc.",
      "tags": ["only tags from <available_tags> that clearly apply — be selective"],
      "confidence": 0.85,
      "correspondent": "the main sender or issuing company/person of this document, or null if unclear. Use a short, clean name without legal suffixes like Ltda, S.A., GmbH",
      "involved_parties": [{"name": "Entity Name", "role": "sender or recipient or subject or other"}]
    }
    """

    body = %{
      model: model,
      stream: false,
      messages: [%{role: "user", content: prompt}],
      format: "json"
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
  def embed(text) do
    {base_url, model} = config()

    body = %{
      model: model,
      input: text
    }

    case Req.post("#{base_url}/api/embed", json: body) do
      {:ok, %{status: 200, body: %{"embeddings" => [embedding | _]}}} ->
        {:ok, embedding}

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
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
      confidence: Map.get(result, "confidence", 0.5),
      correspondent: correspondent,
      involved_parties: involved_parties
    }
  end
end
