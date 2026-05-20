defmodule Seath.Repo.Migrations.CreateDocumentTypes do
  use Ecto.Migration

  def change do
    create table(:document_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:document_types, [:name])
  end
end
