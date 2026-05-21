defmodule Seath.LLM.Tools do
  @moduledoc """
  Tool definitions and execution for LLM function-calling in the RAG chat.

  Provides two tools:
    - `search_documents` — grep-based exact match search
    - `semantic_search` — pgvector embedding similarity search

  Tools follow OpenAI's function-calling schema so they work with any
  provider that supports the `chat_with_tools/3` callback.
  """

  @doc """
  Returns the list of tool definitions available to the LLM.
  """
  def tools do
    [
      %{
        type: "function",
        function: %{
          name: "search_documents",
          description:
            "Search archived documents for exact matches. Use this for queries about specific names, IDs, dates, amounts, or any exact term. Returns document titles and snippets.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{type: "string", description: "The search query"},
              max_results: %{
                type: "integer",
                description: "Maximum results to return",
                default: 5
              }
            },
            required: ["query"]
          }
        }
      },
      %{
        type: "function",
        function: %{
          name: "semantic_search",
          description:
            "Search documents by meaning/semantics. Use this for vague questions, summaries, or when exact terms are unknown. Returns document titles and snippets ranked by relevance.",
          parameters: %{
            type: "object",
            properties: %{
              query: %{type: "string", description: "The semantic search query"},
              max_results: %{
                type: "integer",
                description: "Maximum results to return",
                default: 5
              }
            },
            required: ["query"]
          }
        }
      }
    ]
  end

  @doc """
  Executes a tool by name with the given arguments.

  Returns `{:ok, formatted_result_string}` with human-readable results
  that can be sent back to the LLM as a tool result message.

  Also returns the list of document sources found in `:sources` for
  the ChatLive UI to display.
  """
  def execute("search_documents", %{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)

    results =
      Seath.Retrieval.search(query,
        limit: max_results,
        max_docs: max_results,
        include_docs: true
      )

    format_search_results(results)
  end

  def execute("semantic_search", %{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)

    case Seath.LLM.embed(query) do
      {:ok, embedding} ->
        results =
          Seath.Embeddings.similarity_search(embedding, limit: max_results, min_score: 0.5)

        format_semantic_results(results)

      {:error, _reason} ->
        {:ok, "Semantic search unavailable due to embedding failure.", []}
    end
  end

  def execute(_name, _args) do
    {:ok, "Unknown tool.", []}
  end

  defp format_search_results(results) when is_list(results) and results != [] do
    mapped =
      Enum.map(results, fn r ->
        doc = r.document

        if doc do
          {"- #{doc.title || doc.file_name}\n  #{String.slice(doc.ocr_text || "", 0, 300)}", doc}
        else
          {"- Unknown document (#{r.document_id})", nil}
        end
      end)

    {formatted, sources} = Enum.unzip(mapped)
    sources = Enum.reject(sources, &is_nil/1)
    {:ok, Enum.join(formatted, "\n"), sources}
  end

  defp format_search_results(_results) do
    {:ok, "No results found for the search query.", []}
  end

  defp format_semantic_results(results) when is_list(results) and results != [] do
    mapped =
      Enum.map(results, fn r ->
        doc = r.document

        if doc do
          {"- #{doc.title || doc.file_name} (relevance: #{Float.round(r.score, 2)})\n  #{String.slice(doc.ocr_text || "", 0, 300)}",
           doc}
        else
          {"- Unknown document (relevance: #{Float.round(r.score, 2)})", nil}
        end
      end)

    {formatted, sources} = Enum.unzip(mapped)
    sources = Enum.reject(sources, &is_nil/1)
    {:ok, Enum.join(formatted, "\n"), sources}
  end

  defp format_semantic_results(_results) do
    {:ok, "No semantically similar documents found.", []}
  end
end
