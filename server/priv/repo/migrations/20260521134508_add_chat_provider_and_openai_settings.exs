defmodule Seath.Repo.Migrations.AddChatProviderAndOpenaiSettings do
  use Ecto.Migration

  def change do
    alter table(:settings) do
      add :chat_provider, :string, default: ""
      add :ollama_chat_model, :string, default: "gemma3:27b"
      add :openai_api_key, :string
      add :openai_model, :string, default: "gpt-4o"
      add :openai_base_url, :string, default: "https://api.openai.com/v1"
    end
  end
end
