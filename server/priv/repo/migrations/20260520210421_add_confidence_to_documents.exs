defmodule Seath.Repo.Migrations.AddConfidenceToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :confidence, :float, null: true
    end
  end
end
