defmodule Seath.Repo.Migrations.CreateInvolvedParties do
  use Ecto.Migration

  def change do
    create table(:involved_parties, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :role, :string

      timestamps(type: :utc_datetime)
    end

    create index(:involved_parties, [:document_id])
    create index(:involved_parties, [:name])
  end
end
