defmodule Seath.Repo.Migrations.AddPgvectorAndEmbeddings do
  use Ecto.Migration

  @disable_ddl_transaction true

  def up do
    # Attempt to create the vector extension using Repo.query directly,
    # bypassing the migration runner. If pgvector is not installed on the
    # system, we log a warning and skip the embeddings tables entirely.
    vector_available? =
      case Seath.Repo.query("CREATE EXTENSION IF NOT EXISTS vector") do
        {:ok, _} -> true
        {:error, _} -> false
      end

    if vector_available? do
      create table(:document_embeddings, primary_key: false) do
        add :id, :binary_id, primary_key: true

        add :document_id, references(:documents, on_delete: :delete_all, type: :binary_id),
          null: false

        add :embedding, :vector, size: 1536
        add :model, :string, null: false
        add :chunk_index, :integer, default: 0
        add :chunk_text, :text
        timestamps()
      end

      create index(:document_embeddings, :document_id)
      # Cosine similarity index
      execute(
        "CREATE INDEX document_embeddings_vector_idx ON document_embeddings USING hnsw (embedding vector_cosine_ops)"
      )
    else
      IO.warn("""
      pgvector extension not available — skipping document_embeddings migration.
      To enable vector search, install the pgvector extension:
        - Nix: add pgvector to your environment or flake.nix
        - Apt: sudo apt install postgresql-16-pgvector
        - Manual: https://github.com/pgvector/pgvector#installation
      """)
    end
  end

  def down do
    try do
      drop table(:document_embeddings)
    rescue
      _ -> :ok
    end

    try do
      execute("DROP EXTENSION IF EXISTS vector")
    rescue
      _ -> :ok
    end
  end
end
