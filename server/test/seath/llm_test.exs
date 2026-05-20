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
end
