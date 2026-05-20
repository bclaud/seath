defmodule Seath.LLM.Ollama do
  @moduledoc """
  Ollama LLM provider.

  Uses an Ollama chat model (default: llama3.2) to classify document text
  and return structured metadata (title, document_type, tags, confidence).
  Requires a running Ollama instance.
  Configure via `OLLAMA_BASE_URL` and `OLLAMA_LLM_MODEL` environment
  variables or equivalent config entries.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(text, available_tags, available_types) do
    config = Application.get_env(:seath, __MODULE__, [])

    base_url =
      Keyword.get(config, :base_url) ||
        System.get_env("OLLAMA_BASE_URL", "http://localhost:11434")

    model = Keyword.get(config, :model) || System.get_env("OLLAMA_LLM_MODEL", "llama3.2")

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
        parse_response(content)

      {:ok, %{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, :connection_refused}

      {:error, error} ->
        {:error, error}
    end
  end

  defp parse_response(content) do
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
