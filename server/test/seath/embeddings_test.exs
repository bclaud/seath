defmodule Seath.EmbeddingsTest do
  use Seath.DataCase

  alias Seath.Embeddings
  alias Seath.Documents

  @valid_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "store_embedding!/4" do
    test "stores an embedding for a document" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)

      embedding = Embeddings.store_embedding!(doc.id, vector, "test-model")

      assert embedding.document_id == doc.id
      assert embedding.model == "test-model"
      assert embedding.chunk_index == 0
      assert embedding.chunk_text == nil
    end

    test "stores an embedding with chunk options" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)

      embedding =
        Embeddings.store_embedding!(doc.id, vector, "test-model",
          chunk_index: 1,
          chunk_text: "sample chunk text"
        )

      assert embedding.chunk_index == 1
      assert embedding.chunk_text == "sample chunk text"
    end
  end

  describe "similarity_search/2" do
    test "returns similar archived documents" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :status, "awaiting_review"))

      {:ok, archived_doc} = Documents.transition_status(doc, "archived")

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)
      Embeddings.store_embedding!(archived_doc.id, vector, "test-model")

      # Search with the same vector — should find it with high similarity
      results = Embeddings.similarity_search(vector, min_score: 0.0)

      assert length(results) >= 1
      assert Enum.any?(results, fn %{document: d} -> d.id == archived_doc.id end)
    end

    test "does not return non-archived documents" do
      {:ok, doc} = Documents.create_document(Map.put(@valid_attrs, :status, "pending"))

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)
      Embeddings.store_embedding!(doc.id, vector, "test-model")

      results = Embeddings.similarity_search(vector, min_score: 0.0)

      refute Enum.any?(results, fn %{document: d} -> d.id == doc.id end)
    end

    test "respects min_score filter" do
      {:ok, doc} =
        Documents.create_document(Map.put(@valid_attrs, :status, "awaiting_review"))

      {:ok, archived_doc} = Documents.transition_status(doc, "archived")

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)
      Embeddings.store_embedding!(archived_doc.id, vector, "test-model")

      # Search with min_score above 1.0 (impossible) — should return nothing
      results = Embeddings.similarity_search(vector, min_score: 1.5)

      assert results == []
    end
  end

  describe "delete_for_document/1" do
    test "deletes all embeddings for a document" do
      {:ok, doc} = Documents.create_document(@valid_attrs)

      vector = Enum.map(1..1536, fn _ -> :rand.uniform() - 0.5 end)
      Embeddings.store_embedding!(doc.id, vector, "test-model")
      Embeddings.store_embedding!(doc.id, vector, "test-model", chunk_index: 1)

      assert {2, _} = Embeddings.delete_for_document(doc.id)
      assert Embeddings.similarity_search(vector, min_score: 0.0) == []
    end
  end
end
