defmodule Seath.LLM.ToolsTest do
  use Seath.DataCase

  alias Seath.LLM.Tools

  describe "tools/0" do
    test "returns two tool definitions" do
      assert tools = Tools.tools()
      assert length(tools) == 2

      [search, semantic] = tools

      assert search[:function][:name] == "search_documents"
      assert search[:type] == "function"

      assert semantic[:function][:name] == "semantic_search"
      assert semantic[:type] == "function"
    end

    test "tool definitions have required parameters" do
      [search, semantic] = Tools.tools()

      assert search[:function][:parameters][:required] == ["query"]
      assert semantic[:function][:parameters][:required] == ["query"]
    end
  end

  describe "execute/2" do
    test "returns formatted result for search_documents" do
      # Since there are no documents in the test DB, this should return "No results"
      assert {:ok, result, sources} =
               Tools.execute("search_documents", %{"query" => "nonexistent"})

      assert result == "No results found for the search query."
      assert sources == []
    end

    test "returns unknown tool message for unknown tool" do
      assert {:ok, result, sources} = Tools.execute("unknown_tool", %{})
      assert result == "Unknown tool."
      assert sources == []
    end

    test "search_documents with max_results parameter" do
      assert {:ok, result, sources} =
               Tools.execute("search_documents", %{"query" => "test", "max_results" => 10})

      assert is_binary(result)
      assert sources == []
    end

    test "semantic_search returns full chunk_text and document metadata" do
      {:ok, doc} =
        Seath.Documents.create_document(%{
          file_path: "/uploads/contract.pdf",
          file_name: "contract.pdf",
          file_type: "application/pdf",
          file_size: 2048,
          title: "Solar Panel Installation Contract",
          ocr_text: String.duplicate("Header text. ", 40) <> "Final clause: Warranty is 25 years.",
          status: "awaiting_review"
        })

      {:ok, doc} = Seath.Documents.transition_status(doc, "archived")
      {:ok, vec} = Seath.LLM.embed("warranty period")

      Seath.Embeddings.store_embedding!(doc.id, vec, "bge-m3",
        chunk_index: 1,
        chunk_text: "Final clause: Warranty is 25 years."
      )

      assert {:ok, formatted, [source]} =
               Tools.execute("semantic_search", %{"query" => "warranty period"})

      assert source.id == doc.id
      assert formatted =~ "Solar Panel Installation Contract"
      assert formatted =~ "Final clause: Warranty is 25 years."
    end
  end
end
