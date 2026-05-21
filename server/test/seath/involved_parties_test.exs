defmodule Seath.InvolvedPartiesTest do
  use Seath.DataCase

  alias Seath.InvolvedParties
  alias Seath.InvolvedParties.InvolvedParty
  alias Seath.Documents

  @valid_doc_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  @valid_attrs %{name: "John Doe", role: "signer"}
  @invalid_attrs %{name: nil, role: nil}

  setup do
    {:ok, document} = Documents.create_document(@valid_doc_attrs)
    %{document: document}
  end

  describe "create_involved_party/1" do
    test "creates an involved party with valid attrs", %{document: document} do
      attrs = Map.put(@valid_attrs, :document_id, document.id)
      assert {:ok, %InvolvedParty{} = party} = InvolvedParties.create_involved_party(attrs)
      assert party.name == "John Doe"
      assert party.role == "signer"
      assert party.document_id == document.id
    end

    test "returns error for invalid attrs", %{document: document} do
      attrs = Map.put(@invalid_attrs, :document_id, document.id)
      assert {:error, %Ecto.Changeset{}} = InvolvedParties.create_involved_party(attrs)
    end

    test "requires document_id" do
      assert {:error, %Ecto.Changeset{}} = InvolvedParties.create_involved_party(@valid_attrs)
    end
  end

  describe "list_parties_by_document/1" do
    test "returns all parties for a document", %{document: document} do
      attrs = Map.put(@valid_attrs, :document_id, document.id)
      {:ok, _party1} = InvolvedParties.create_involved_party(attrs)

      {:ok, _party2} =
        InvolvedParties.create_involved_party(Map.put(attrs, :name, "Jane Doe"))

      parties = InvolvedParties.list_parties_by_document(document.id)
      assert length(parties) == 2
    end

    test "returns empty list when no parties", %{document: document} do
      assert InvolvedParties.list_parties_by_document(document.id) == []
    end
  end

  describe "replace_parties_for_document/2" do
    test "replaces all parties for a document", %{document: document} do
      # First create some parties
      attrs = Map.put(@valid_attrs, :document_id, document.id)
      {:ok, _party1} = InvolvedParties.create_involved_party(attrs)

      # Replace with new parties
      new_parties = [
        %{name: "Acme Corp", role: "company"},
        %{name: "Bob Smith", role: "witness"}
      ]

      assert {:ok, _} = InvolvedParties.replace_parties_for_document(document.id, new_parties)

      parties = InvolvedParties.list_parties_by_document(document.id)
      assert length(parties) == 2
      assert Enum.any?(parties, &(&1.name == "Acme Corp"))
      assert Enum.any?(parties, &(&1.name == "Bob Smith"))
    end
  end

  describe "delete_involved_party/1" do
    test "deletes an involved party", %{document: document} do
      attrs = Map.put(@valid_attrs, :document_id, document.id)
      {:ok, party} = InvolvedParties.create_involved_party(attrs)

      assert {:ok, %InvolvedParty{}} = InvolvedParties.delete_involved_party(party)
      assert InvolvedParties.list_parties_by_document(document.id) == []
    end
  end
end
