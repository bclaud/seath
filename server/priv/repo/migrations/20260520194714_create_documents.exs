defmodule Seath.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :file_path, :string, null: false
      add :file_name, :string, null: false
      add :file_type, :string, null: false
      add :file_size, :bigint, null: false
      add :ocr_text, :text
      add :status, :string, null: false, default: "pending"
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:documents, [:status])
  end
end
