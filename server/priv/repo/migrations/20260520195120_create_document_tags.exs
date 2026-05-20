defmodule Seath.Repo.Migrations.CreateDocumentTags do
  use Ecto.Migration

  def change do
    create table(:document_tags, primary_key: false) do
      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tag_id, references(:tags, type: :binary_id, on_delete: :delete_all), null: false
    end

    create unique_index(:document_tags, [:document_id, :tag_id])
    create index(:document_tags, [:tag_id])
  end
end
