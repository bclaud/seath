defmodule Seath.DocumentsTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Documents.Document

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "create_document/1" do
    test "creates a document with valid attrs" do
      assert {:ok, %Document{} = document} = Documents.create_document(@valid_attrs)
      assert document.file_path == "/uploads/test.pdf"
      assert document.file_name == "test.pdf"
      assert document.file_type == "application/pdf"
      assert document.file_size == 1024
      assert document.status == "pending"
      assert document.title == nil
      assert document.ocr_text == nil
      assert document.archived_at == nil
    end

    test "returns error when file_path is missing" do
      attrs = Map.delete(@valid_attrs, :file_path)
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "can't be blank" in errors_on(changeset).file_path
    end

    test "returns error when file_name is missing" do
      attrs = Map.delete(@valid_attrs, :file_name)
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "can't be blank" in errors_on(changeset).file_name
    end

    test "returns error when file_type is missing" do
      attrs = Map.delete(@valid_attrs, :file_type)
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "can't be blank" in errors_on(changeset).file_type
    end

    test "returns error when file_size is missing" do
      attrs = Map.delete(@valid_attrs, :file_size)
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "can't be blank" in errors_on(changeset).file_size
    end

    test "returns error when file_size is not positive" do
      attrs = Map.put(@valid_attrs, :file_size, 0)
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "must be greater than 0" in errors_on(changeset).file_size
    end

    test "returns error when status is invalid" do
      attrs = Map.put(@valid_attrs, :status, "invalid_status")
      assert {:error, %Ecto.Changeset{} = changeset} = Documents.create_document(attrs)
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "state_transition/2" do
    test "allows pending -> processing" do
      assert :ok = Document.state_transition("pending", "processing")
    end

    test "allows processing -> awaiting_review" do
      assert :ok = Document.state_transition("processing", "awaiting_review")
    end

    test "allows awaiting_review -> archived" do
      assert :ok = Document.state_transition("awaiting_review", "archived")
    end

    test "allows awaiting_review -> rejected" do
      assert :ok = Document.state_transition("awaiting_review", "rejected")
    end

    test "allows rejected -> pending" do
      assert :ok = Document.state_transition("rejected", "pending")
    end

    test "rejects pending -> archived (skip states)" do
      assert {:error, reason} = Document.state_transition("pending", "archived")
      assert reason =~ "invalid transition"
    end

    test "rejects archived -> pending (backwards)" do
      assert {:error, reason} = Document.state_transition("archived", "pending")
      assert reason =~ "invalid transition"
    end

    test "rejects processing -> pending (backwards)" do
      assert {:error, reason} = Document.state_transition("processing", "pending")
      assert reason =~ "invalid transition"
    end
  end

  describe "transition_status/2" do
    setup do
      {:ok, document} = Documents.create_document(@valid_attrs)
      %{document: document}
    end

    test "transitions pending -> processing", %{document: document} do
      assert {:ok, updated} = Documents.transition_status(document, "processing")
      assert updated.status == "processing"
    end

    test "transitions processing -> awaiting_review", %{document: document} do
      {:ok, doc} = Documents.transition_status(document, "processing")
      assert {:ok, updated} = Documents.transition_status(doc, "awaiting_review")
      assert updated.status == "awaiting_review"
    end

    test "transitions awaiting_review -> archived and sets archived_at", %{document: document} do
      {:ok, doc} = Documents.transition_status(document, "processing")
      {:ok, doc} = Documents.transition_status(doc, "awaiting_review")
      assert {:ok, updated} = Documents.transition_status(doc, "archived")
      assert updated.status == "archived"
      assert updated.archived_at != nil
    end

    test "transitions awaiting_review -> rejected", %{document: document} do
      {:ok, doc} = Documents.transition_status(document, "processing")
      {:ok, doc} = Documents.transition_status(doc, "awaiting_review")
      assert {:ok, updated} = Documents.transition_status(doc, "rejected")
      assert updated.status == "rejected"
    end

    test "transitions rejected -> pending (re-process)", %{document: document} do
      {:ok, doc} = Documents.transition_status(document, "processing")
      {:ok, doc} = Documents.transition_status(doc, "awaiting_review")
      {:ok, doc} = Documents.transition_status(doc, "rejected")
      assert {:ok, updated} = Documents.transition_status(doc, "pending")
      assert updated.status == "pending"
    end

    test "rejects invalid transition", %{document: document} do
      assert {:error, reason} = Documents.transition_status(document, "archived")
      assert reason =~ "invalid transition"
    end
  end

  describe "store_ocr_text/2" do
    setup do
      {:ok, document} = Documents.create_document(@valid_attrs)
      %{document: document}
    end

    test "stores OCR text and transitions to processing", %{document: document} do
      assert {:ok, updated} = Documents.store_ocr_text(document, "Extracted text content")
      assert updated.ocr_text == "Extracted text content"
      assert updated.status == "processing"
    end
  end

  describe "list_documents/0" do
    test "returns all documents" do
      {:ok, doc1} = Documents.create_document(@valid_attrs)
      {:ok, doc2} = Documents.create_document(Map.put(@valid_attrs, :file_name, "test2.pdf"))

      docs = Documents.list_documents()
      assert length(docs) == 2
      assert Enum.any?(docs, &(&1.id == doc1.id))
      assert Enum.any?(docs, &(&1.id == doc2.id))
    end

    test "returns empty list when no documents exist" do
      assert Documents.list_documents() == []
    end
  end

  describe "list_by_status/1" do
    test "filters documents by status" do
      {:ok, doc1} = Documents.create_document(@valid_attrs)
      {:ok, doc2} = Documents.create_document(Map.put(@valid_attrs, :file_name, "test2.pdf"))
      {:ok, doc2} = Documents.transition_status(doc2, "processing")

      pending = Documents.list_by_status("pending")
      processing = Documents.list_by_status("processing")

      assert length(pending) == 1
      assert hd(pending).id == doc1.id
      assert length(processing) == 1
      assert hd(processing).id == doc2.id
    end
  end

  describe "get_document!/1" do
    test "returns the document with the given id" do
      {:ok, document} = Documents.create_document(@valid_attrs)
      assert Documents.get_document!(document.id).id == document.id
    end

    test "raises when document does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Documents.get_document!(Ecto.UUID.generate())
      end
    end
  end

  describe "update_document/2" do
    setup do
      {:ok, document} = Documents.create_document(@valid_attrs)
      %{document: document}
    end

    test "updates document attributes", %{document: document} do
      assert {:ok, updated} = Documents.update_document(document, %{title: "My Document"})
      assert updated.title == "My Document"
    end

    test "returns error with invalid data", %{document: document} do
      assert {:error, %Ecto.Changeset{}} = Documents.update_document(document, %{file_size: -1})
    end
  end

  describe "validate_file_size/1" do
    test "accepts files within the limit" do
      assert :ok = Documents.validate_file_size(1024)
      assert :ok = Documents.validate_file_size(50 * 1024 * 1024)
    end

    test "rejects files exceeding 50MB" do
      assert {:error, reason} = Documents.validate_file_size(50 * 1024 * 1024 + 1)
      assert reason =~ "file size exceeds maximum"
    end
  end

  describe "ingest/2" do
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

    test "ingests a PDF file end-to-end" do
      temp_path = create_temp_file("PDF content", ".pdf")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "report.pdf")
      assert document.status == "pending"
      assert document.file_name == "report.pdf"
      assert document.file_type == "application/pdf"
      assert document.file_size > 0
      assert File.exists?(document.file_path)
    end

    test "ingests a PNG file" do
      temp_path = create_temp_file("PNG data", ".png")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "image.png")
      assert document.file_type == "image/png"
      assert document.status == "pending"
    end

    test "ingests a JPG file" do
      temp_path = create_temp_file("JPG data", ".jpg")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "photo.jpg")
      assert document.file_type == "image/jpeg"
    end

    test "ingests a JPEG file" do
      temp_path = create_temp_file("JPEG data", ".jpeg")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "photo.jpeg")
      assert document.file_type == "image/jpeg"
    end

    test "ingests a TIFF file" do
      temp_path = create_temp_file("TIFF data", ".tiff")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "scan.tiff")
      assert document.file_type == "image/tiff"
    end

    test "ingests a TXT file" do
      temp_path = create_temp_file("plain text", ".txt")

      assert {:ok, %Document{} = document} = Documents.ingest(temp_path, "notes.txt")
      assert document.file_type == "text/plain"
    end

    test "rejects unsupported file types (.exe)" do
      temp_path = create_temp_file("binary", ".exe")

      assert {:error, reason} = Documents.ingest(temp_path, "malware.exe")
      assert reason =~ "unsupported file type"
    end

    test "rejects unsupported file types (.sh)" do
      temp_path = create_temp_file("#!/bin/sh", ".sh")

      assert {:error, reason} = Documents.ingest(temp_path, "script.sh")
      assert reason =~ "unsupported file type"
    end

    test "rejects unsupported file types (.html)" do
      temp_path = create_temp_file("<html></html>", ".html")

      assert {:error, reason} = Documents.ingest(temp_path, "page.html")
      assert reason =~ "unsupported file type"
    end

    test "rejects files without extension" do
      temp_path = create_temp_file("no extension", "")

      assert {:error, reason} = Documents.ingest(temp_path, "noext")
      assert reason =~ "unsupported file type"
    end

    test "rejects duplicate content" do
      content = "unique content for dedup test #{System.unique_integer([:positive])}"

      temp_path1 = create_temp_file(content, ".pdf")
      assert {:ok, %Document{content_hash: hash}} = Documents.ingest(temp_path1, "original.pdf")
      assert hash != nil
      assert String.length(hash) == 64

      temp_path2 = create_temp_file(content, ".pdf")
      assert {:error, reason} = Documents.ingest(temp_path2, "copy.pdf")
      assert reason =~ "duplicate"
      assert reason =~ "original.pdf"
    end

    test "allows different content with same filename" do
      temp_path1 = create_temp_file("version one", ".pdf")
      assert {:ok, %{}} = Documents.ingest(temp_path1, "report.pdf")

      temp_path2 = create_temp_file("version two", ".pdf")
      assert {:ok, %{}} = Documents.ingest(temp_path2, "report.pdf")
    end
  end

  # --- Helpers ---

  defp create_temp_file(content, extension) do
    tmp_dir = System.tmp_dir!()
    path = Path.join(tmp_dir, "seath_test_#{Ecto.UUID.generate()}#{extension}")
    File.write!(path, content)

    on_exit(fn ->
      if File.exists?(path), do: File.rm(path)
    end)

    path
  end
end
