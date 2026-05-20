defmodule Seath.Embeddings.Embedding do
  @moduledoc """
  Schema for document embeddings stored in the `document_embeddings` table.

  Each embedding represents a vectorized chunk of document text, enabling
  similarity search over the document corpus.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "document_embeddings" do
    field :embedding, Pgvector.Ecto.Vector
    field :model, :string
    field :chunk_index, :integer, default: 0
    field :chunk_text, :string
    belongs_to :document, Seath.Documents.Document

    timestamps()
  end

  @doc false
  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [:document_id, :embedding, :model, :chunk_index, :chunk_text])
    |> validate_required([:document_id, :embedding, :model])
  end
end
