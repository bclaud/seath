defmodule Seath.OCR.OllamaTest do
  use Seath.DataCase

  alias Seath.OCR.Ollama

  test "returns error when Ollama is not running" do
    result = Ollama.extract("nonexistent.pdf")
    assert {:error, _reason} = result
  end
end
