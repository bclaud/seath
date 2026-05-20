defmodule Seath.TestLLMProvider do
  @moduledoc """
  Test LLM provider that returns a classification with specific tags and document type.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(_text, _available_tags, _available_types) do
    {:ok,
     %{
       title: "Test Invoice",
       document_type: "invoice",
       tags: ["invoice", "finance"],
       confidence: 0.9
     }}
  end
end
