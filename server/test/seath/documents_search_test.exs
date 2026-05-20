defmodule Seath.DocumentsSearchTest do
  use Seath.DataCase

  alias Seath.Documents

  setup do
    {:ok, doc1} =
      Documents.create_document(%{
        file_path: "/tmp/invoice.pdf",
        file_name: "invoice_march.pdf",
        file_type: "application/pdf",
        file_size: 1024,
        status: "archived",
        title: "March Invoice",
        ocr_text: "Invoice #12345 for consulting services rendered in March 2024. Total: $5,000"
      })

    {:ok, doc2} =
      Documents.create_document(%{
        file_path: "/tmp/receipt.pdf",
        file_name: "receipt.pdf",
        file_type: "application/pdf",
        file_size: 2048,
        status: "archived",
        title: "Office Supplies Receipt",
        ocr_text: "Receipt for office supplies purchased at Staples. Paper, pens, notebooks."
      })

    {:ok, doc3} =
      Documents.create_document(%{
        file_path: "/tmp/contract.pdf",
        file_name: "contract.pdf",
        file_type: "application/pdf",
        file_size: 4096,
        status: "archived",
        title: "Employment Contract",
        ocr_text:
          "Employment agreement between Company Inc and John Doe. Start date: April 1, 2024."
      })

    {:ok, doc1: doc1, doc2: doc2, doc3: doc3}
  end

  test "search finds documents by title", %{doc1: doc1} do
    results = Documents.search("invoice")
    assert length(results) >= 1
    assert Enum.any?(results, &(&1.id == doc1.id))
  end

  test "search finds documents by OCR text content", %{doc2: doc2} do
    results = Documents.search("staples")
    assert length(results) >= 1
    assert Enum.any?(results, &(&1.id == doc2.id))
  end

  test "search returns empty for no matches" do
    results = Documents.search("xyznonexistent")
    assert results == []
  end

  test "search with empty string returns empty" do
    results = Documents.search("")
    assert results == []
  end

  test "search ranks results by relevance", %{doc1: doc1} do
    results = Documents.search("invoice")
    # doc1 has "invoice" in both title and OCR text, should rank highest
    assert hd(results).id == doc1.id
  end
end
