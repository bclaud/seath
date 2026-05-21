defmodule Seath.Settings.Setting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "settings" do
    field :ocr_provider, :string, default: ""
    field :llm_provider, :string, default: ""
    field :chat_provider, :string, default: ""
    field :azure_endpoint, :string
    field :azure_key, :string
    field :ollama_base_url, :string, default: "http://localhost:11434"
    field :ollama_ocr_model, :string, default: "llama3.2-vision"
    field :ollama_llm_model, :string, default: "gemma3:27b"
    field :ollama_chat_model, :string, default: "gemma3:27b"
    field :openai_api_key, :string
    field :openai_model, :string, default: "gpt-4o"
    field :openai_base_url, :string, default: "https://api.openai.com/v1"
    timestamps()
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [
      :id,
      :ocr_provider,
      :llm_provider,
      :chat_provider,
      :azure_endpoint,
      :azure_key,
      :ollama_base_url,
      :ollama_ocr_model,
      :ollama_llm_model,
      :ollama_chat_model,
      :openai_api_key,
      :openai_model,
      :openai_base_url
    ])
  end
end
