defmodule Seath.Workers.WorkerBroadcastTest do
  use Seath.DataCase

  alias Seath.Documents

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "PubSub broadcasts" do
    test "OCR worker broadcasts processing status" do
      Phoenix.PubSub.subscribe(Seath.PubSub, "documents")

      {:ok, doc} = Documents.create_document(@valid_attrs)

      Seath.Workers.OCRWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :ocr)

      assert_receive {:document_updated, updated}, 1_000
      assert updated.id == doc.id
      assert updated.status == "processing"
    end

    test "classify worker broadcasts awaiting_review status" do
      Phoenix.PubSub.subscribe(Seath.PubSub, "documents")

      {:ok, doc} = Documents.create_document(@valid_attrs)

      {:ok, doc} =
        Documents.update_document(doc, %{ocr_text: "Some Mock text from Mock Corp", status: "processing"})

      Seath.Workers.ClassifyWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      assert_receive {:document_updated, updated}, 1_000
      assert updated.id == doc.id
      assert updated.status == "awaiting_review"
    end

    test "archive worker broadcasts archived status" do
      Phoenix.PubSub.subscribe(Seath.PubSub, "documents")

      {:ok, doc} = Documents.create_document(Map.put(@valid_attrs, :status, "awaiting_review"))

      Seath.Workers.ArchiveWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive)

      assert_receive {:document_updated, updated}, 1_000
      assert updated.id == doc.id
      assert updated.status == "archived"
    end
  end
end
