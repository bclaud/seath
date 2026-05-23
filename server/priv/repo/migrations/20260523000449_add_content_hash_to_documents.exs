defmodule Seath.Repo.Migrations.AddContentHashToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :content_hash, :string
    end

    create index(:documents, [:content_hash])
  end
end
