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
      assert is_binary(hd(embeddings).model)
      assert hd(embeddings).chunk_index == 0
      assert hd(embeddings).chunk_text == "Sample document text for embedding."
    end

    test "splits long OCR text into overlapping chunks and replaces old embeddings" do
      long_text =
        1..60
        |> Enum.map_join("\n\n", fn idx ->
          "Clause #{idx}: This is a detailed contractual paragraph with specific obligations and payment schedules."
        end)

      {:ok, doc} =
        Documents.create_document(
          @valid_attrs
          |> Map.put(:title, "Master Service Agreement")
          |> Map.put(:ocr_text, long_text)
        )

      EmbedWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      embeddings =
        Seath.Repo.all(Embedding)
        |> Enum.sort_by(& &1.chunk_index)

      assert length(embeddings) >= 3
      assert Enum.map(embeddings, & &1.chunk_index) == Enum.to_list(0..(length(embeddings) - 1))
      assert Enum.all?(embeddings, &(is_binary(&1.chunk_text) and &1.chunk_text != ""))

      # Re-running replaces previous chunks rather than duplicating
      EmbedWorker.new(%{"document_id" => doc.id})
      |> Oban.insert!()

      Oban.drain_queue(queue: :classify)

      assert length(Seath.Repo.all(Embedding)) == length(embeddings)
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
