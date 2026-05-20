defmodule Seath.Repo.Migrations.CreateSavedSearches do
  use Ecto.Migration

  def change do
    create table(:saved_searches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :query, :string
      add :tag_ids, {:array, :binary_id}
      add :document_type_id, references(:document_types, type: :binary_id, on_delete: :nilify_all)
      add :status_filter, :string
      add :date_from, :date
      add :date_to, :date
      timestamps()
    end

    create index(:saved_searches, :name)
  end
end
