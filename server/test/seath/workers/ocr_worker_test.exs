defmodule Seath.Workers.OCRWorkerTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Workers.OCRWorker

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
    test "extracts OCR text and stores it on the document", %{document: document} do
      OCRWorker.new(%{"document_id" => document.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :ocr)

      updated = Documents.get_document!(document.id)
      assert updated.ocr_text == "Mock extracted text from document."
      assert updated.status == "processing"
    end

    test "returns error when document does not exist" do
      OCRWorker.new(%{"document_id" => Ecto.UUID.generate()})
      |> Oban.insert!()

      Oban.drain_queue(queue: :ocr)

      # The job should be discarded since document doesn't exist
      # No document should have been updated
      assert Documents.list_documents() |> Enum.all?(&(&1.ocr_text == nil))
    end
  end
end
