defmodule Seath.LLM.OpenAI do
  @moduledoc """
  OpenAI (or OpenAI-compatible) LLM provider.

  Uses the OpenAI Chat Completions API to classify document text,
  generate embeddings, and provide conversational chat responses.

  Configure via environment variables:
    - `OPENAI_API_KEY` (required)
    - `OPENAI_BASE_URL` (default: "https://api.openai.com/v1")
    - `OPENAI_LLM_MODEL` (default: "gpt-4o")

  This provider supports function-calling via `chat_with_tools/3`.
  """
  @behaviour Seath.LLM.Provider

  @doc false
  def config do
    api_key =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:api_key) ||
        System.get_env("OPENAI_API_KEY")

    base_url =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:base_url) ||
        System.get_env("OPENAI_BASE_URL", "https://api.openai.com/v1")

    model =
      Application.get_env(:seath, __MODULE__, [])
      |> Keyword.get(:model) ||
        System.get_env("OPENAI_LLM_MODEL", "gpt-4o")

    {api_key, base_url, model}
  end

  @impl true
  def classify(text, available_tags, available_types, opts \\ []) do
    {api_key, base_url, model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      do_classify(text, available_tags, available_types, opts, api_key, base_url, model)
    end
  end

  defp do_classify(text, available_tags, available_types, opts, api_key, base_url, model) do
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
      "document_type": "the single best matching type from <available_document_types>, or null if none match",
      "tags": ["only tags from <available_tags> that clearly apply"],
      "confidence": 0.85,
      "correspondent": "the main sender or issuing company/person of this document, or null if unclear",
      "involved_parties": [{"name": "Entity Name", "role": "sender or recipient or subject or other"}]
    }
    """

    headers = [
      {"Authorization", "Bearer #{api_key}"},
      {"Content-Type", "application/json"}
    ]

    body = %{
      model: model,
      messages: [%{role: "user", content: prompt}],
      response_format: %{type: "json_object"}
    }

    case Req.post("#{base_url}/chat/completions",
           json: body,
           headers: headers,
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        parse_classification(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def embed(text) do
    {api_key, base_url, _model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: "text-embedding-3-small",
        input: text
      }

      case Req.post("#{base_url}/embeddings",
             json: body,
             headers: headers,
             receive_timeout: 30_000
           ) do
        {:ok, %{status: 200, body: %{"data" => [%{"embedding" => embedding} | _]}}} ->
          {:ok, embedding}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def chat(messages, opts) do
    {api_key, base_url, model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      system_prompt = Keyword.get(opts, :system)
      messages = maybe_prepend_system(messages, system_prompt)

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        messages: messages
      }

      case Req.post("#{base_url}/chat/completions",
             json: body,
             headers: headers
           ) do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
          {:ok, content}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def chat_stream(messages, opts, stream_to) do
    {api_key, base_url, model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      system_prompt = Keyword.get(opts, :system)
      messages = maybe_prepend_system(messages, system_prompt)

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"},
        {"Accept", "text/event-stream"}
      ]

      body = %{
        model: model,
        messages: messages,
        stream: true
      }

      case Req.post("#{base_url}/chat/completions",
             json: body,
             headers: headers,
             into: :self
           ) do
        {:ok, %{status: 200} = resp} ->
          full_response = stream_sse(resp.body, stream_to)
          {:ok, full_response}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def chat_with_tools(messages, tools, opts) do
    {api_key, base_url, model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      system_prompt = Keyword.get(opts, :system)
      messages = maybe_prepend_system(messages, system_prompt)

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        messages: messages,
        tools: tools
      }

      case Req.post("#{base_url}/chat/completions",
             json: body,
             headers: headers,
             receive_timeout: 120_000
           ) do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => message} | _]}}} ->
          parse_tool_response(message)

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def ocr_vision(image_data, opts \\ []) do
    {api_key, base_url, model} = config()

    if is_nil(api_key) do
      {:error, :not_configured}
    else
      prompt =
        Keyword.get(opts, :prompt) ||
          "Just transcribe the text in this image and preserve the formatting and layout (high quality OCR). Be thorough and extract ALL text including numbers, amounts, dates, invoice numbers, tax IDs, and other structured data. Use markdown format but without a code block."

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = %{
        model: model,
        messages: [
          %{
            role: "user",
            content: [
              %{type: "text", text: prompt},
              %{
                type: "image_url",
                image_url: %{url: "data:image/png;base64,#{Base.encode64(image_data)}"}
              }
            ]
          }
        ],
        max_tokens: 4096
      }

      case Req.post("#{base_url}/chat/completions",
             json: body,
             headers: headers,
             receive_timeout: 120_000
           ) do
        {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
          {:ok, String.trim(content)}

        {:ok, %{status: status, body: body}} ->
          {:error, {:unexpected_response, status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp maybe_prepend_system(messages, nil), do: messages
  defp maybe_prepend_system(messages, prompt), do: [%{role: "system", content: prompt} | messages]

  defp parse_tool_response(%{"tool_calls" => calls} = message) do
    content = Map.get(message, "content", "")

    tool_calls =
      Enum.map(calls, fn call ->
        %{
          id: call["id"],
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

  defp stream_sse(async_body, stream_to) do
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
            case line do
              "data: [DONE]" ->
                []

              "data: " <> json ->
                case Jason.decode(json) do
                  {:ok, %{"choices" => [%{"delta" => %{"content" => token}} | _]}} ->
                    send(stream_to, {:stream_token, token})
                    [token]

                  _ ->
                    []
                end

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
