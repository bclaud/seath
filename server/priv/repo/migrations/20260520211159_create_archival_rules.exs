defmodule Seath.Repo.Migrations.CreateArchivalRules do
  use Ecto.Migration

  def change do
    create table(:archival_rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :tag_id, references(:tags, on_delete: :delete_all, type: :binary_id), null: false
      add :age_days, :integer, null: false, default: 90
      add :target_status, :string, null: false, default: "archived"
      add :enabled, :boolean, default: true
      timestamps()
    end

    create index(:archival_rules, :tag_id)
    create unique_index(:archival_rules, [:name])
  end
end
