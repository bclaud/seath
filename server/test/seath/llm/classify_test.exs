defmodule Seath.LLM.ClassifyTest do
  use Seath.DataCase

  alias Seath.LLM.Classify

  describe "classify_document/4 with custom provider" do
    setup do
      # Use the test classify provider that returns proper JSON
      Application.put_env(:seath, :llm_provider, Seath.TestClassifyProvider)

      on_exit(fn ->
        Application.put_env(:seath, :llm_provider, Seath.LLM.Mock)
      end)

      :ok
    end

    test "classifies document and returns all fields" do
      text = "Invoice #1234 from Acme Corp for $5,000.00"
      tags = ["invoice", "receipt", "personal", "finance"]
      types = ["invoice", "receipt", "contract"]
      correspondents = ["Acme Corp", "Globex Inc"]

      assert {:ok, result} = Classify.classify_document(text, tags, types, correspondents)
      assert result.title == "Invoice #1234"
      assert result.document_type == "invoice"
      assert result.tags == ["invoice", "finance", "acme"]
      assert result.confidence == 0.95
      assert result.correspondent == "Acme Corporation"
      assert length(result.involved_parties) == 2

      first_party = Enum.at(result.involved_parties, 0)
      assert first_party.name == "Acme Corp"
      assert first_party.role == "sender"
    end

    test "extract_metadata returns parsed metadata" do
      assert {:ok, metadata} =
               Classify.extract_metadata("Some invoice text", ["invoice", "receipt"])

      assert metadata.title == "Invoice #1234"
      assert metadata.document_type == "invoice"
      assert metadata.confidence == 0.95
    end

    test "extract_tags returns list of tags" do
      assert {:ok, tags} =
               Classify.extract_tags("Invoice text", "Invoice #1234", ["invoice", "finance"])

      assert tags == ["invoice", "finance", "acme"]
    end

    test "extract_correspondent returns a name" do
      assert {:ok, name} =
               Classify.extract_correspondent("Invoice from Acme", "Invoice", ["Acme Corp"])

      assert name == "Acme Corporation"
    end

    test "extract_involved_parties returns list of parties" do
      assert {:ok, parties} =
               Classify.extract_involved_parties("Invoice from Acme Corp to John Doe")

      assert length(parties) == 2

      acme = Enum.find(parties, fn p -> p.name == "Acme Corp" end)
      assert acme.role == "sender"

      john = Enum.find(parties, fn p -> p.name == "John Doe" end)
      assert john.role == "recipient"
    end
  end

  describe "fallback behavior with Mock provider" do
    test "returns error when provider returns invalid JSON" do
      # With the default Mock provider, chat/2 returns plain text, not JSON
      text = "Some document text"
      result = Classify.classify_document(text, [], [])
      assert {:error, _reason} = result
    end
  end
end
