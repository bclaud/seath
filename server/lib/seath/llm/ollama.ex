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

  @impl true
  def classify(text, available_tags, available_types) do
    {base_url, model} = config()
    do_classify(text, available_tags, available_types, base_url, model)
  end

  defp do_classify(text, available_tags, available_types, base_url, model) do
    tags_list = Enum.join(available_tags, ", ")
    types_list = Enum.join(available_types, ", ")

    prompt = """
    You are a document classification assistant. Analyze the following document text and return a JSON object with:
    - "title": a concise title for the document (max 80 chars)
    - "document_type": the best matching type from this list: [#{types_list}], or null if none match
    - "tags": an array of relevant tags from this list: [#{tags_list}]. Only include tags that clearly apply.
    - "confidence": a number between 0.0 and 1.0 indicating how confident you are in this classification

    Document text:
    #{String.slice(text, 0, 4000)}

    Return ONLY the JSON object, no other text.
    """

    body = %{
      model: model,
      stream: false,
      messages: [%{role: "user", content: prompt}],
      format: "json"
    }

    case Req.post("#{base_url}/api/chat", json: body) do
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

  defp maybe_prepend_system(messages, nil), do: messages
  defp maybe_prepend_system(messages, prompt), do: [%{role: "system", content: prompt} | messages]

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
        {:ok,
         %{
           title: title,
           document_type: Map.get(result, "document_type"),
           tags: Map.get(result, "tags", []),
           confidence: Map.get(result, "confidence", 0.5)
         }}

      {:ok, _} ->
        {:error, :invalid_response_format}

      {:error, _} ->
        # Try to extract JSON from the response if it's wrapped in markdown or extra text
        case Regex.run(~r/\{[\s\S]*\}/, content) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, %{"title" => title} = result} ->
                {:ok,
                 %{
                   title: title,
                   document_type: Map.get(result, "document_type"),
                   tags: Map.get(result, "tags", []),
                   confidence: Map.get(result, "confidence", 0.5)
                 }}

              _ ->
                {:error, :invalid_response_format}
            end

          nil ->
            {:error, :invalid_response_format}
        end
    end
  end
end
