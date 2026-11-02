defmodule Seath.Workers.EmbedWorker do
  @moduledoc """
  Oban worker that generates and stores chunked document embeddings.

  Fetches a document, splits its OCR text into overlapping semantic chunks,
  generates an embedding vector for each chunk using the configured LLM provider,
  and stores them in the `document_embeddings` table.
  """
  use Oban.Worker, queue: :classify, max_attempts: 3

  alias Seath.Documents

  @chunk_size 2_000
  @chunk_overlap 300

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => id}}) do
    with {:ok, doc} <- fetch_document(id),
         {:ok, text} <- validate_ocr_text(doc),
         chunks = chunk_text(text),
         {:ok, embedded_chunks} <- embed_chunks(doc, chunks) do
      Seath.Embeddings.delete_for_document(doc.id)

      Enum.each(embedded_chunks, fn {chunk, idx, vector} ->
        Seath.Embeddings.store_embedding!(doc.id, vector, configured_model(),
          chunk_index: idx,
          chunk_text: chunk
        )
      end)

      :ok
    end
  end

  @doc """
  Splits document OCR text into overlapping chunks of at most `@chunk_size` bytes,
  preferring paragraph, newline, or sentence boundaries.
  """
  def chunk_text(text) when is_binary(text) do
    trimmed = String.trim(text)

    if byte_size(trimmed) <= @chunk_size do
      [trimmed]
    else
      do_split_chunks(trimmed, @chunk_size, @chunk_overlap, [])
    end
  end

  defp do_split_chunks(text, chunk_size, _overlap, acc) when byte_size(text) <= chunk_size do
    Enum.reverse([String.trim(text) | acc])
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_chunks(text, chunk_size, overlap, acc) do
    take = min(chunk_size, byte_size(text))
    break_at = find_break_point(text, take)

    chunk_part = binary_slice_utf8(text, 0, break_at) |> String.trim()
    remaining_start = max(0, break_at - overlap)
    remaining = safe_utf8_tail(text, remaining_start)

    # Guard against non-advancing break points
    if byte_size(remaining) >= byte_size(text) do
      forced_tail = safe_utf8_tail(text, take)
      do_split_chunks(forced_tail, chunk_size, overlap, [chunk_part | acc])
    else
      do_split_chunks(remaining, chunk_size, overlap, [chunk_part | acc])
    end
  end

  defp find_break_point(text, max_size) do
    half = div(max_size, 2)
    search_region = binary_slice_utf8(text, 0, max_size)

    last_para = find_last_substring(search_region, "\n\n")
    last_newline = find_last_substring(search_region, "\n")
    last_period = find_last_substring(search_region, ". ")

    cond do
      last_para && last_para > half -> last_para + 2
      last_newline && last_newline > half -> last_newline + 1
      last_period && last_period > half -> last_period + 2
      true -> byte_size(search_region)
    end
  end

  defp find_last_substring(string, pattern) do
    do_find_last(string, pattern, 0, nil)
  end

  defp do_find_last(string, pattern, offset, last_found) do
    remaining = byte_size(string) - offset

    if remaining <= 0 do
      last_found
    else
      case :binary.match(string, pattern, [{:scope, {offset, remaining}}]) do
        {pos, len} -> do_find_last(string, pattern, pos + len, pos)
        :nomatch -> last_found
      end
    end
  end

  # Ensures we slice on valid UTF-8 codepoint boundaries
  defp binary_slice_utf8(text, start_byte, max_len) do
    raw = :binary.part(text, start_byte, min(max_len, byte_size(text) - start_byte))
    trim_incomplete_utf8(raw)
  end

  defp safe_utf8_tail(text, start_byte) when start_byte >= byte_size(text), do: ""

  defp safe_utf8_tail(text, start_byte) do
    raw = :binary.part(text, start_byte, byte_size(text) - start_byte)
    drop_leading_continuation_bytes(raw)
  end

  defp trim_incomplete_utf8(bin) do
    case String.chunk(bin, :valid) do
      [] -> ""
      chunks -> Enum.filter(chunks, &String.valid?/1) |> Enum.join()
    end
  end

  defp drop_leading_continuation_bytes(<<b, rest::binary>>)
       when Bitwise.band(b, 0b1100_0000) == 0b1000_0000 do
    drop_leading_continuation_bytes(rest)
  end

  defp drop_leading_continuation_bytes(bin), do: trim_incomplete_utf8(bin)

  defp embed_chunks(doc, chunks) do
    title_prefix =
      if doc.title && doc.title != "" do
        "Document: #{doc.title}\n\n"
      else
        ""
      end

    chunks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {chunk, idx}, {:ok, acc} ->
      input_text = title_prefix <> chunk

      case Seath.LLM.embed(input_text) do
        {:ok, vector} -> {:cont, {:ok, [{chunk, idx, vector} | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp fetch_document(id) do
    case Documents.get_document(id) do
      nil -> {:error, :not_found}
      doc -> {:ok, doc}
    end
  end

  defp validate_ocr_text(%{ocr_text: text}) when not is_nil(text) and text != "", do: {:ok, text}

  defp validate_ocr_text(_), do: {:error, :no_ocr_text}

  defp configured_model do
    Application.get_env(:seath, Seath.LLM.Ollama, [])
    |> Keyword.get(:embed_model, "bge-m3")
  end
end
