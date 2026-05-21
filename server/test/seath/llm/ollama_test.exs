defmodule Seath.LLM.OllamaTest do
  use Seath.DataCase

  alias Seath.LLM.Ollama

  setup do
    # Use an unreachable URL so tests don't depend on a running Ollama instance
    Application.put_env(:seath, Seath.LLM.Ollama,
      base_url: "http://localhost:19999",
      model: "test-model"
    )

    on_exit(fn ->
      Application.delete_env(:seath, Seath.LLM.Ollama)
    end)

    :ok
  end

  test "returns error when Ollama is not reachable" do
    result = Ollama.classify("some text", [], [])
    assert {:error, _reason} = result
  end

  test "classify with available tags and types also returns error when Ollama is not reachable" do
    result =
      Ollama.classify("invoice text", ["invoice", "receipt", "personal"], ["financial", "legal"])

    assert {:error, _reason} = result
  end

  test "chat returns error when Ollama is not reachable" do
    result = Ollama.chat([%{role: "user", content: "Hello"}], [])
    assert {:error, _reason} = result
  end

  test "chat_stream returns error when Ollama is not reachable" do
    result = Ollama.chat_stream([%{role: "user", content: "Hello"}], [], self())
    assert {:error, _reason} = result
  end
end
