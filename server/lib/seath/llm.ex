defmodule Seath.LLM do
  @moduledoc """
  LLM context — delegates to the configured LLM provider.

  Configure via `config :seath, :llm_provider, Seath.LLM.Ollama`
  or set the `LLM_PROVIDER` env var. Available providers:
    - Seath.LLM.Ollama
  """

  @doc """
  Returns the configured LLM provider module, or `nil` if none is configured.
  """
  def impl do
    Application.get_env(:seath, :llm_provider)
  end

  @doc """
  Classifies document text using the configured LLM provider.

  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def classify(text, available_tags, available_types) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.classify(text, available_tags, available_types)
    end
  end

  @doc """
  Generates an embedding vector for the given text using the configured LLM provider.

  Returns `{:error, :not_configured}` if no LLM provider is configured.
  """
  def embed(text) do
    case impl() do
      nil -> {:error, :not_configured}
      provider -> provider.embed(text)
    end
  end
end
