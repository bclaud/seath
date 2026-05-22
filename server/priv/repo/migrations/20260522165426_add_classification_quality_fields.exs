defmodule Seath.Repo.Migrations.AddClassificationQualityFields do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :llm_reasoning, :text
      add :verification_data, :map
      add :classification_attempts, :integer, default: 0
    end
  end
end
