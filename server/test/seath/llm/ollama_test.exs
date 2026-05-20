defmodule Seath.LLM.OllamaTest do
  use Seath.DataCase

  alias Seath.LLM.Ollama

  test "returns error when Ollama is not running" do
    result = Ollama.classify("some text", [], [])
    assert {:error, _reason} = result
  end

  test "classify with available tags and types also returns error when Ollama is not running" do
    result =
      Ollama.classify("invoice text", ["invoice", "receipt", "personal"], ["financial", "legal"])

    assert {:error, _reason} = result
  end
end
