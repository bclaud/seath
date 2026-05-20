defmodule Seath.Repo.Migrations.CreateCorrespondents do
  use Ecto.Migration

  def change do
    create table(:correspondents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :color, :string
      timestamps()
    end

    create unique_index(:correspondents, :name)

    alter table(:documents) do
      add :correspondent_id, references(:correspondents, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:documents, :correspondent_id)
  end
end
