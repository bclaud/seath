defmodule Seath.DocumentsMetadataTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Tags
  alias Seath.DocumentTypes

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "build_metadata_header/1" do
    test "includes basic document fields" do
      {:ok, doc} = Documents.create_document(@valid_attrs)
      {:ok, updated} = Documents.update_document(doc, %{title: "My Document"})

      header = Documents.build_metadata_header(updated)

      assert header =~ "title: My Document"
      assert header =~ "tags:"
      assert header =~ "document_type:"
      assert header =~ "correspondent:"
      assert header =~ "status: pending"
      assert header =~ "date:"
      assert header =~ "---"
    end

    test "includes tags when present" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      {:ok, tag} = Tags.create_tag(%{name: "finance"})
      {:ok, _} = Tags.add_tag_to_document(doc, tag)

      updated = Documents.get_document!(doc.id)
      header = Documents.build_metadata_header(updated)

      assert header =~ "tags: finance"
    end

    test "includes multiple tags" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      {:ok, tag1} = Tags.create_tag(%{name: "finance"})
      {:ok, tag2} = Tags.create_tag(%{name: "urgent"})
      {:ok, _} = Tags.add_tag_to_document(doc, tag1)
      {:ok, _} = Tags.add_tag_to_document(doc, tag2)

      updated = Documents.get_document!(doc.id)
      header = Documents.build_metadata_header(updated)

      assert header =~ "tags: finance, urgent" or header =~ "tags: urgent, finance"
    end

    test "includes document type when present" do
      {:ok, doc} = Documents.create_document(@valid_attrs)
      {:ok, type} = DocumentTypes.create_type(%{name: "invoice"})
      {:ok, updated} = Documents.update_document(doc, %{document_type_id: type.id})

      header = Documents.build_metadata_header(updated)
      assert header =~ "document_type: invoice"
    end

    test "header is separated from body by ---" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :ocr_text, "Invoice body text"))

      header = Documents.build_metadata_header(doc)

      assert String.contains?(header, "---\n")
    end
  end

  describe "build_text_file_content/1" do
    test "includes body text after header" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :ocr_text, "This is the OCR text body."))

      content = Documents.build_text_file_content(doc)

      assert String.contains?(content, "---\n")
      assert String.contains?(content, "This is the OCR text body.")
      assert String.starts_with?(content, "title:")
    end

    test "handles nil OCR text" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      content = Documents.build_text_file_content(doc)

      assert String.contains?(content, "---\n")
    end
  end
end
