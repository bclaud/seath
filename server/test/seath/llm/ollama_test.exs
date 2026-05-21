defmodule Seath.LLM.OllamaTest do
  use Seath.DataCase

  alias Seath.LLM.Ollama

  setup do
    # Use an unreachable URL so tests don't depend on a running Ollama instance
    Application.put_env(:seath, Seath.LLM.Ollama,
      base_url: "http://localhost:19999",
      model: "test-model",
      vision_model: "test-vision-model"
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

  test "ocr_vision returns error when Ollama is not reachable" do
    result = Ollama.ocr_vision(<<0, 1, 2, 3>>)
    assert {:error, _reason} = result
  end

  test "ocr_vision accepts custom prompt option" do
    result =
      Ollama.ocr_vision(<<0, 1, 2, 3>>,
        prompt: "Custom OCR prompt with structured data extraction."
      )

    assert {:error, _reason} = result
  end

  test "vision_config returns the configured vision model" do
    {_base_url, model} = Ollama.vision_config()
    assert model == "test-vision-model"
  end

  describe "chat_with_tools/3" do
    test "returns error when Ollama is not reachable" do
      tools = [
        %{
          type: "function",
          function: %{
            name: "search_documents",
            description: "Search documents",
            parameters: %{
              type: "object",
              properties: %{query: %{type: "string"}},
              required: ["query"]
            }
          }
        }
      ]

      result = Ollama.chat_with_tools([%{role: "user", content: "Hello"}], tools, [])
      assert {:error, _reason} = result
    end
  end
end
