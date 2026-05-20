defmodule Seath.LLM do
  @moduledoc """
  LLM context — delegates to the configured LLM provider.
  """

  @doc """
  Returns the configured LLM provider module.
  """
  def impl do
    Application.get_env(:seath, :llm_provider, Seath.LLM.Mock)
  end

  @doc """
  Classifies document text using the configured LLM provider.

  Returns a classification result with title, document_type, tags, and confidence.
  """
  def classify(text, available_tags, available_types) do
    impl().classify(text, available_tags, available_types)
  end
end
