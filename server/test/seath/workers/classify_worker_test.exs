defmodule Seath.Workers.ClassifyWorkerTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Tags
  alias Seath.DocumentTypes
  alias Seath.Workers.ClassifyWorker

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  setup do
    {:ok, document} = Documents.create_document(@valid_attrs)
    %{document: document}
  end

  describe "perform/1" do
    test "classifies document with OCR text and transitions to awaiting_review", %{
      document: document
    } do
      # Give the document OCR text including text that matches mock entity output
      {:ok, document} =
        Documents.update_document(document, %{
          ocr_text: "Some Mock Corp extracted text with amounts",
          status: "processing"
        })

      ClassifyWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      updated = Documents.get_document!(document.id)
      assert updated.title == "Mock Document"
      assert updated.status == "awaiting_review"
      assert updated.confidence > 0
    end

    test "returns error when document does not exist" do
      ClassifyWorker.new(%{"document_id" => Ecto.UUID.generate()})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      # No document should have been updated to awaiting_review
      refute Documents.list_documents() |> Enum.any?(&(&1.status == "awaiting_review"))
    end

    test "returns error when document has no OCR text", %{document: document} do
      ClassifyWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      updated = Documents.get_document!(document.id)
      assert updated.status == "error"
      assert updated.error_message != nil
    end

    test "returns error when document has empty OCR text", %{document: document} do
      {:ok, document} = Documents.update_document(document, %{ocr_text: ""})

      ClassifyWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      updated = Documents.get_document!(document.id)
      assert updated.status == "error"
      assert updated.error_message != nil
    end

    test "creates tags if they don't exist", %{document: document} do
      # Override the LLM provider to return specific tags
      Application.put_env(:seath, :llm_provider, Seath.TestLLMProvider)

      {:ok, document} =
        Documents.update_document(document, %{
          ocr_text: "Invoice text from Acme Corp with amount R$ 1.500,00",
          status: "processing"
        })

      ClassifyWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      # Verify the tag was created
      tag = Tags.get_tag_by_name("invoice")
      assert tag != nil
      assert tag.name == "invoice"

      # Verify the document has the tag
      updated = Documents.get_document!(document.id) |> Seath.Repo.preload(:tags)
      assert Enum.any?(updated.tags, &(&1.name == "invoice"))
    after
      Application.put_env(:seath, :llm_provider, Seath.LLM.Mock)
    end

    test "sets document type if matched", %{document: document} do
      # Create a document type first
      {:ok, doc_type} = DocumentTypes.create_type(%{name: "invoice"})

      # Override the LLM provider to return a specific document type
      Application.put_env(:seath, :llm_provider, Seath.TestLLMProvider)

      {:ok, document} =
        Documents.update_document(document, %{
          ocr_text: "Invoice text from Acme Corp with amount R$ 1.500,00",
          status: "processing"
        })

      ClassifyWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      updated = Documents.get_document!(document.id)
      assert updated.document_type_id == doc_type.id
    after
      Application.put_env(:seath, :llm_provider, Seath.LLM.Mock)
    end
  end
end
