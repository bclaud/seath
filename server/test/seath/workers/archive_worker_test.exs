defmodule Seath.Workers.ArchiveWorkerTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Workers.ArchiveWorker

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "perform/1" do
    test "archives a document in awaiting_review status" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :status, "awaiting_review"))

      ArchiveWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive)

      updated = Documents.get_document!(doc.id)
      assert updated.status == "archived"
      assert updated.archived_at != nil
    end

    test "returns error for non-existent document" do
      ArchiveWorker.new(%{"document_id" => Ecto.UUID.generate()})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive)

      # No document should have been archived
      refute Documents.list_documents() |> Enum.any?(&(&1.status == "archived"))
    end

    test "returns error for document not in awaiting_review" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      ArchiveWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :archive)

      updated = Documents.get_document!(doc.id)
      assert updated.status == "pending"
    end
  end
end
