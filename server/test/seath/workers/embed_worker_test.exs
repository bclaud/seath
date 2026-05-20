defmodule Seath.Workers.EmbedWorkerTest do
  use Seath.DataCase

  alias Seath.Documents
  alias Seath.Workers.EmbedWorker
  alias Seath.Embeddings.Embedding

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "perform/1" do
    test "generates and stores embedding for a document with OCR text" do
      {:ok, doc} =
        Documents.create_document(
          Map.put(@valid_attrs, :ocr_text, "Sample document text for embedding.")
        )

      EmbedWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      embeddings = Seath.Repo.all(Embedding)
      assert length(embeddings) == 1
      assert hd(embeddings).document_id == doc.id
      assert hd(embeddings).model == "llama3.2"
      assert hd(embeddings).chunk_index == 0
    end

    test "returns error when document does not exist" do
      EmbedWorker.new(%{"document_id" => Ecto.UUID.generate()})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      assert Seath.Repo.all(Embedding) == []
    end

    test "returns error when document has no OCR text" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      EmbedWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      assert Seath.Repo.all(Embedding) == []
    end

    test "returns error when document has empty OCR text" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :ocr_text, ""))

      EmbedWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      assert Seath.Repo.all(Embedding) == []
    end
  end
end
