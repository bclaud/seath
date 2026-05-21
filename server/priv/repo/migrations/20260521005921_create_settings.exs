defmodule Seath.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ocr_provider, :string, default: ""
      add :llm_provider, :string, default: ""
      add :azure_endpoint, :string
      add :azure_key, :string
      add :ollama_base_url, :string, default: "http://localhost:11434"
      add :ollama_ocr_model, :string, default: "llava"
      add :ollama_llm_model, :string, default: "llama3.2"
      timestamps()
    end
  end
end
