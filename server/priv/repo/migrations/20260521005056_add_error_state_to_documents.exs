defmodule Seath.Repo.Migrations.AddErrorStateToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :error_message, :text
    end
  end
end
