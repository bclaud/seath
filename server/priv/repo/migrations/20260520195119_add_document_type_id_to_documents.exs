defmodule Seath.Repo.Migrations.AddDocumentTypeIdToDocuments do
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :document_type_id, references(:document_types, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:documents, [:document_type_id])
  end
end
