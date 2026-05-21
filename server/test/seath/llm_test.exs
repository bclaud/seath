defmodule Seath.LLMTest do
  use Seath.DataCase

  alias Seath.LLM

  describe "impl/0" do
    test "returns the configured LLM provider" do
      assert LLM.impl() == Seath.LLM.Mock
    end
  end

  describe "classify/3" do
    test "delegates to the configured provider" do
      assert {:ok, result} = LLM.classify("some text", [], [])
      assert result.title == "Untitled Document"
      assert result.document_type == nil
      assert result.tags == []
      assert result.confidence == 0.5
    end
  end

  describe "chat/2" do
    test "returns a conversational response from the configured provider" do
      assert {:ok, response} = LLM.chat([%{role: "user", content: "Hello"}])
      assert is_binary(response)
      assert response != ""
    end

    test "accepts system prompt option" do
      messages = [%{role: "user", content: "What documents do I have?"}]
      assert {:ok, _response} = LLM.chat(messages, system: "You are a helpful assistant.")
    end
  end

  describe "chat_stream/3" do
    test "streams tokens to the given pid" do
      test_pid = self()

      assert {:ok, response} =
               LLM.chat_stream([%{role: "user", content: "Hello"}], [], test_pid)

      assert is_binary(response)
      assert_received {:stream_token, _token}
    end
  end

  describe "ocr_vision/2" do
    test "delegates to the configured provider" do
      assert {:ok, text} = LLM.ocr_vision(<<0, 1, 2, 3>>)
      assert is_binary(text)
      assert String.contains?(text, "Invoice")
    end

    test "returns error when no provider is configured" do
      Application.put_env(:seath, :llm_provider, nil)

      assert {:error, :not_configured} = LLM.ocr_vision(<<0, 1, 2, 3>>)
    after
      Application.put_env(:seath, :llm_provider, Seath.LLM.Mock)
    end
  end
end
