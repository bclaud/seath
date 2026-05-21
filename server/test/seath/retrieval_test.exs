defmodule Seath.RetrievalTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Retrieval

  @test_upload_dir "test/tmp/uploads"

  setup do
    Application.put_env(:seath, :storage, upload_dir: @test_upload_dir)

    on_exit(fn ->
      if File.exists?(@test_upload_dir) do
        File.rm_rf!(@test_upload_dir)
      end

      Application.put_env(:seath, :storage, upload_dir: "priv/uploads")
    end)

    :ok
  end

  describe "search/2" do
    test "returns results when query matches OCR text" do
      {:ok, doc} =
        Documents.create_document(%{
          file_path: "/uploads/test.pdf",
          file_name: "test.pdf",
          file_type: "application/pdf",
          file_size: 1024,
          ocr_text: "This document contains an invoice from Acme Corporation for $500."
        })

      # store_ocr_text writes the text file
      {:ok, _updated} = Documents.store_ocr_text(doc, doc.ocr_text)

      results = Retrieval.search("invoice")
      assert length(results) > 0
      assert Enum.any?(results, &(&1.document_id == doc.id))
    end

    test "returns multiple results for different documents" do
      {:ok, doc1} =
        Documents.create_document(%{
          file_path: "/uploads/doc1.pdf",
          file_name: "doc1.pdf",
          file_type: "application/pdf",
          file_size: 1024,
          ocr_text: "Invoice from Acme Corp for services rendered."
        })

      {:ok, doc2} =
        Documents.create_document(%{
          file_path: "/uploads/doc2.pdf",
          file_name: "doc2.pdf",
          file_type: "application/pdf",
          file_size: 2048,
          ocr_text: "Contract with Beta LLC for Q3 2025."
        })

      {:ok, _} = Documents.store_ocr_text(doc1, doc1.ocr_text)
      {:ok, _} = Documents.store_ocr_text(doc2, doc2.ocr_text)

      # Search for a term only in doc1
      results = Retrieval.search("Acme")
      assert length(results) == 1
      assert hd(results).document_id == doc1.id

      # Search for a term only in doc2
      results = Retrieval.search("Beta")
      assert length(results) == 1
      assert hd(results).document_id == doc2.id
    end

    test "returns empty list for no matches" do
      results = Retrieval.search("nonexistent_term_xyzzy")
      assert results == []
    end

    test "returns empty list for empty query" do
      results = Retrieval.search("")
      assert results == []
    end

    test "returns match details with line numbers" do
      {:ok, doc} =
        Documents.create_document(%{
          file_path: "/uploads/test.pdf",
          file_name: "test.pdf",
          file_type: "application/pdf",
          file_size: 1024,
          ocr_text: "Important report data here."
        })

      {:ok, _} = Documents.store_ocr_text(doc, doc.ocr_text)

      results = Retrieval.search("Important")
      assert length(results) > 0

      result = Enum.find(results, &(&1.document_id == doc.id))
      assert result != nil
      assert result.match_count > 0
      assert length(result.matches) > 0

      match = hd(result.matches)
      assert Map.has_key?(match, :line_number)
      assert Map.has_key?(match, :line)
    end

    test "grep_command returns rg when available" do
      {cmd, args} = Retrieval.grep_command()
      assert cmd == "rg"
      assert "--no-heading" in args
      assert "--line-number" in args
    end

    test "respects limit option" do
      {:ok, doc} =
        Documents.create_document(%{
          file_path: "/uploads/test.pdf",
          file_name: "test.pdf",
          file_type: "application/pdf",
          file_size: 1024,
          ocr_text: "the the the the the the the"
        })

      {:ok, _} = Documents.store_ocr_text(doc, doc.ocr_text)

      results = Retrieval.search("the", limit: 3)
      assert length(results) > 0

      result = Enum.find(results, &(&1.document_id == doc.id))
      if result, do: assert(length(result.matches) <= 3)
    end
  end
end
