defmodule Seath.LLM.Mock do
  @moduledoc """
  Mock LLM provider for development and testing.
  """
  @behaviour Seath.LLM.Provider

  @impl true
  def classify(_text, _available_tags, _available_types) do
    {:ok,
     %{
       title: "Untitled Document",
       document_type: nil,
       tags: [],
       confidence: 0.5
     }}
  end
end
