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

    grep_results =
      Seath.Retrieval.search(query,
        limit: max_results,
        max_docs: max_results,
        include_docs: true
      )

    # Supplement with PostgreSQL full-text / ilike search if grep returns fewer than max_results
    results =
      if length(grep_results) < max_results do
        seen_ids = MapSet.new(grep_results, & &1.document_id)

        db_docs =
          Seath.Documents.search(query)
          |> Enum.reject(&MapSet.member?(seen_ids, &1.id))
          |> Enum.take(max_results - length(grep_results))
          |> Enum.map(fn doc ->
            %{document_id: doc.id, document: doc, match_count: 1, matches: []}
          end)

        grep_results ++ db_docs
      else
        grep_results
      end

    format_search_results(results)
  end

  def execute("semantic_search", %{"query" => query} = args) do
    max_results = Map.get(args, "max_results", 5)

    case Seath.LLM.embed(query) do
      {:ok, embedding} ->
        results =
          Seath.Embeddings.similarity_search(embedding, limit: max_results, min_score: 0.35)

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
        doc = r[:document]

        if doc do
          doc = Seath.Repo.preload(doc, [:tags, :document_type, :correspondent])
          meta = format_doc_metadata(doc)
          snippet = extract_match_context(doc, Map.get(r, :matches, []))

          {"- #{doc.title || doc.file_name}#{meta}\n  #{snippet}", doc}
        else
          {"- Unknown document (#{r[:document_id]})", nil}
        end
      end)

    {formatted, sources} = Enum.unzip(mapped)
    sources = Enum.reject(sources, &is_nil/1) |> Enum.uniq_by(& &1.id)
    {:ok, Enum.join(formatted, "\n\n"), sources}
  end

  defp format_search_results(_results) do
    {:ok, "No results found for the search query.", []}
  end

  defp format_semantic_results(results) when is_list(results) and results != [] do
    mapped =
      Enum.map(results, fn r ->
        doc = r[:document]
        emb = r[:embedding]

        if doc do
          doc = Seath.Repo.preload(doc, [:tags, :document_type, :correspondent])
          meta = format_doc_metadata(doc)

          chunk_str =
            case emb && emb.chunk_text do
              text when is_binary(text) and text != "" ->
                text

              _ ->
                String.slice(doc.ocr_text || "", 0, 1800)
            end

          {"- #{doc.title || doc.file_name}#{meta} (relevance: #{Float.round(r.score, 2)})\n  #{chunk_str}",
           doc}
        else
          {"- Unknown document (relevance: #{Float.round(r.score, 2)})", nil}
        end
      end)

    {formatted, sources} = Enum.unzip(mapped)
    sources = Enum.reject(sources, &is_nil/1) |> Enum.uniq_by(& &1.id)
    {:ok, Enum.join(formatted, "\n\n"), sources}
  end

  defp format_semantic_results(_results) do
    {:ok, "No semantically similar documents found.", []}
  end

  defp format_doc_metadata(doc) do
    parts =
      [
        doc.document_type && "type: #{doc.document_type.name}",
        doc.correspondent && "correspondent: #{doc.correspondent.name}",
        doc.tags != [] && is_list(doc.tags) &&
          "tags: #{Enum.map_join(doc.tags, ", ", & &1.name)}"
      ]
      |> Enum.filter(&is_binary/1)

    if parts == [], do: "", else: " [#{Enum.join(parts, " | ")}]"
  end

  defp extract_match_context(doc, matches) when is_list(matches) and matches != [] do
    matched_lines =
      matches
      |> Enum.take(8)
      |> Enum.map_join("\n  ", fn m -> Map.get(m, :line, "") end)
      |> String.trim()

    header_slice = String.slice(doc.ocr_text || "", 0, 1200)

    if matched_lines != "" and not String.contains?(header_slice, matched_lines) do
      "#{header_slice}\n  ...\n  Matched lines:\n  #{matched_lines}"
    else
      String.slice(doc.ocr_text || "", 0, 1800)
    end
  end

  defp extract_match_context(doc, _matches) do
    String.slice(doc.ocr_text || "", 0, 1800)
  end
end
