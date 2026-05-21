defmodule Seath.Retrieval do
  @moduledoc """
  Context for grep-based document retrieval over OCR text files.

  Provides functions to search document text files using `rg` (ripgrep)
  with fallback to `grep -rn`. Returns ranked results with document IDs,
  match context, and line numbers for use in RAG chat and classification
  context injection.

  This complements embedding-based semantic search with exact-match
  retrieval for names, IDs, dates, and other precise queries.
  """

  alias Seath.Documents
  alias Seath.Storage

  @doc """
  Searches document OCR text files using grep.

  Returns a list of maps with:
    - `:document_id` — the document UUID
    - `:line_number` — line number of the match
    - `:line` — the matching line text
    - `:document` — the preloaded document struct (optional, fetched if not nil)

  Returns `[]` for empty or nil queries.

  ## Options
    * `:limit` — max results per document (default 5)
    * `:max_docs` — max documents to return (default 20)
    * `:include_docs` — whether to preload and include document structs (default true)
    * `:status` — filter by document status (e.g. "archived"), nil for all
  """
  @spec search(String.t(), keyword()) :: [map()]
  def search(query, opts \\ []) when is_binary(query) do
    if query == "" or query == nil do
      []
    else
      limit = Keyword.get(opts, :limit, 5)
      max_docs = Keyword.get(opts, :max_docs, 20)
      include_docs = Keyword.get(opts, :include_docs, true)
      status_filter = Keyword.get(opts, :status)

      case find_matching_files(query) do
        {:ok, raw_results} ->
          results = parse_results(raw_results, query)

          results
          |> group_by_document()
          |> maybe_filter_by_status(status_filter)
          |> truncate_lines_per_doc(limit)
          |> maybe_load_documents(include_docs)
          |> rank_results(query)
          |> Enum.take(max_docs)
          |> format_results()

        {:error, _reason} ->
          []
      end
    end
  end

  @doc """
  Returns the grep command to use (prefers `rg`, falls back to `grep -rn`).

  Used internally and for logging/debugging.
  """
  def grep_command do
    case System.find_executable("rg") do
      nil -> {"grep", ~w(-rn --include=\*.txt)}
      _ -> {"rg", ~w(--no-heading --line-number -S)}
    end
  end

  # --- Private helpers ---

  defp find_matching_files(query) do
    {cmd, args} = grep_command()

    # Escape the query for shell safety — use the command's own arg handling
    full_args = args ++ [query, Storage.upload_dir()]

    case System.cmd(cmd, full_args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, 1} ->
        # rg/grep returns exit code 1 when no matches found
        if String.trim(output) == "" do
          {:ok, ""}
        else
          {:ok, output}
        end

      {error, _exit_code} ->
        {:error, error}
    end
  end

  defp parse_results("", _query), do: []

  defp parse_results(output, _query) do
    upload_dir = Storage.upload_dir()

    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      # The format is: path:line_number:content (rg)
      # or path-line_number-content (grep with context)
      case parse_line(line, upload_dir) do
        nil -> nil
        result -> result
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_line(line, upload_dir) do
    # rg format: path:line_number:content
    # We need to handle paths like: /path/to/uploads/doc_id/doc_id.txt:42:some text
    case String.split(line, ":", parts: 3) do
      [path, line_num, content] ->
        doc_id = extract_document_id(path, upload_dir)

        if doc_id do
          %{document_id: doc_id, line_number: String.to_integer(line_num), line: content}
        end

      _ ->
        nil
    end
  end

  defp extract_document_id(path, upload_dir) do
    # Path pattern: {upload_dir}/{document_id}/{document_id}.txt
    rest = String.trim_leading(path, upload_dir <> "/")
    parts = String.split(rest, "/")

    case parts do
      [doc_id, _filename] when byte_size(doc_id) == 36 ->
        doc_id

      _ ->
        nil
    end
  end

  defp group_by_document(results) do
    results
    |> Enum.group_by(& &1.document_id)
  end

  defp maybe_filter_by_status(groups, nil), do: groups

  defp maybe_filter_by_status(groups, status) do
    Map.filter(groups, fn {doc_id, _lines} ->
      case Documents.get_document(doc_id) do
        nil -> false
        doc -> doc.status == status
      end
    end)
  end

  defp truncate_lines_per_doc(groups, limit) do
    Map.new(groups, fn {doc_id, lines} ->
      {doc_id, Enum.take(lines, limit)}
    end)
  end

  defp maybe_load_documents(groups, true) do
    # Fetch all referenced documents in a single query
    doc_ids = Map.keys(groups)
    docs = Documents.get_documents_by_ids(doc_ids)

    doc_map = Map.new(docs, fn doc -> {doc.id, doc} end)

    Map.new(groups, fn {doc_id, lines} ->
      {doc_id, %{document: Map.get(doc_map, doc_id), lines: lines}}
    end)
  end

  defp maybe_load_documents(groups, false) do
    Map.new(groups, fn {doc_id, lines} ->
      {doc_id, %{document: nil, lines: lines}}
    end)
  end

  defp rank_results(groups, _query) do
    # Sort by number of matches (more matches = higher rank)
    groups
    |> Enum.sort_by(fn {_doc_id, %{lines: lines}} -> length(lines) end, :desc)
  end

  defp format_results(groups) do
    Enum.map(groups, fn {doc_id, %{document: doc, lines: lines}} ->
      %{
        document_id: doc_id,
        document: doc,
        match_count: length(lines),
        matches: lines
      }
    end)
  end
end
