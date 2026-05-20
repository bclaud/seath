defmodule Seath.Embeddings do
  @moduledoc """
  Context for managing document embeddings.

  Provides functions to store embeddings, perform cosine similarity searches,
  and clean up embeddings for removed documents.
  """
  import Ecto.Query
  alias Seath.Repo

  @doc """
  Stores an embedding vector for a document.

  ## Options
    * `:chunk_index` - the chunk number (default 0)
    * `:chunk_text` - the text that was embedded (optional)
  """
  def store_embedding!(document_id, embedding_vec, model, opts \\ []) do
    %Seath.Embeddings.Embedding{}
    |> Seath.Embeddings.Embedding.changeset(%{
      document_id: document_id,
      embedding: embedding_vec,
      model: model,
      chunk_index: Keyword.get(opts, :chunk_index, 0),
      chunk_text: Keyword.get(opts, :chunk_text)
    })
    |> Repo.insert!()
  end

  @doc """
  Finds documents similar to a given query embedding using cosine distance.

  Only searches archived documents.

  ## Options
    * `:limit` - max results (default 5)
    * `:min_score` - minimum similarity score (default 0.7)
  """
  def similarity_search(query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    min_score = Keyword.get(opts, :min_score, 0.7)

    from(e in Seath.Embeddings.Embedding,
      join: d in assoc(e, :document),
      where: d.status == "archived",
      select: %{
        embedding: e,
        document: d,
        score: fragment("1 - (embedding <=> ?)", type(^query_embedding, Pgvector.Ecto.Vector))
      },
      order_by: fragment("embedding <=> ?", type(^query_embedding, Pgvector.Ecto.Vector)),
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.filter(fn %{score: score} -> score >= min_score end)
  end

  @doc """
  Deletes all embeddings for a given document.
  """
  def delete_for_document(document_id) do
    from(e in Seath.Embeddings.Embedding, where: e.document_id == ^document_id)
    |> Repo.delete_all()
  end
end
