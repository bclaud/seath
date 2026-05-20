defmodule Seath.Repo.Migrations.AddSearchVectorToDocuments do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE documents ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      setweight(to_tsvector('english', coalesce(title, '')), 'A') ||
      setweight(to_tsvector('english', coalesce(ocr_text, '')), 'B') ||
      setweight(to_tsvector('english', coalesce(file_name, '')), 'C')
    ) STORED
    """

    execute "CREATE INDEX documents_search_idx ON documents USING GIN (search_vector)"
  end

  def down do
    execute "DROP INDEX IF EXISTS documents_search_idx"
    execute "ALTER TABLE documents DROP COLUMN IF EXISTS search_vector"
  end
end
