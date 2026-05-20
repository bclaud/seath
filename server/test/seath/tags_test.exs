defmodule Seath.TagsTest do
  use Seath.DataCase

  alias Seath.Tags
  alias Seath.Tags.Tag
  alias Seath.Documents

  @valid_attrs %{name: "important", color: "#FF5733"}
  @update_attrs %{name: "urgent", color: "#C70039"}

  @doc_attrs %{
    file_path: "/uploads/test.pdf",
    file_name: "test.pdf",
    file_type: "application/pdf",
    file_size: 1024
  }

  describe "list_tags/0" do
    test "returns all tags" do
      {:ok, tag1} = Tags.create_tag(%{name: "tag1"})
      {:ok, tag2} = Tags.create_tag(%{name: "tag2"})

      tags = Tags.list_tags()
      assert length(tags) == 2
      assert Enum.any?(tags, &(&1.id == tag1.id))
      assert Enum.any?(tags, &(&1.id == tag2.id))
    end

    test "returns empty list when no tags exist" do
      assert Tags.list_tags() == []
    end
  end

  describe "get_tag!/1" do
    test "returns the tag with the given id" do
      {:ok, tag} = Tags.create_tag(@valid_attrs)
      assert Tags.get_tag!(tag.id).id == tag.id
    end

    test "raises when tag does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Tags.get_tag!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_tag/1" do
    test "creates a tag with valid attrs" do
      assert {:ok, %Tag{} = tag} = Tags.create_tag(@valid_attrs)
      assert tag.name == "important"
      assert tag.color == "#FF5733"
    end

    test "creates a tag without color" do
      assert {:ok, %Tag{} = tag} = Tags.create_tag(%{name: "minimal"})
      assert tag.name == "minimal"
      assert tag.color == nil
    end

    test "returns error when name is missing" do
      assert {:error, %Ecto.Changeset{} = changeset} = Tags.create_tag(%{color: "#FF5733"})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error when name is not unique" do
      assert {:ok, _tag} = Tags.create_tag(@valid_attrs)
      assert {:error, %Ecto.Changeset{} = changeset} = Tags.create_tag(@valid_attrs)
      assert errors_on(changeset).name
    end
  end

  describe "update_tag/2" do
    setup do
      {:ok, tag} = Tags.create_tag(@valid_attrs)
      %{tag: tag}
    end

    test "updates tag attributes", %{tag: tag} do
      assert {:ok, updated} = Tags.update_tag(tag, @update_attrs)
      assert updated.name == "urgent"
      assert updated.color == "#C70039"
    end

    test "returns error with invalid data", %{tag: tag} do
      assert {:error, %Ecto.Changeset{}} = Tags.update_tag(tag, %{name: nil})
    end

    test "returns error when name is not unique", %{tag: tag} do
      {:ok, _other} = Tags.create_tag(%{name: "urgent"})
      assert {:error, %Ecto.Changeset{} = changeset} = Tags.update_tag(tag, %{name: "urgent"})
      assert errors_on(changeset).name
    end
  end

  describe "delete_tag/1" do
    test "deletes the tag" do
      {:ok, tag} = Tags.create_tag(@valid_attrs)
      assert {:ok, %Tag{}} = Tags.delete_tag(tag)
      assert_raise Ecto.NoResultsError, fn -> Tags.get_tag!(tag.id) end
    end
  end

  describe "add_tag_to_document/2" do
    setup do
      {:ok, document} = Documents.create_document(@doc_attrs)
      {:ok, tag} = Tags.create_tag(@valid_attrs)
      %{document: document, tag: tag}
    end

    test "adds a tag to a document", %{document: document, tag: tag} do
      assert {:ok, updated} = Tags.add_tag_to_document(document, tag)
      updated = Repo.preload(updated, :tags)
      assert length(updated.tags) == 1
      assert hd(updated.tags).id == tag.id
    end

    test "does not duplicate tags", %{document: document, tag: tag} do
      {:ok, updated} = Tags.add_tag_to_document(document, tag)
      {:ok, updated} = Tags.add_tag_to_document(updated, tag)
      updated = Repo.preload(updated, :tags)
      assert length(updated.tags) == 1
    end
  end

  describe "remove_tag_from_document/2" do
    setup do
      {:ok, document} = Documents.create_document(@doc_attrs)
      {:ok, tag} = Tags.create_tag(@valid_attrs)
      {:ok, document} = Tags.add_tag_to_document(document, tag)
      %{document: document, tag: tag}
    end

    test "removes a tag from a document", %{document: document, tag: tag} do
      assert {:ok, updated} = Tags.remove_tag_from_document(document, tag)
      updated = Repo.preload(updated, :tags)
      assert updated.tags == []
    end

    test "is a no-op when tag is not on document", %{document: document} do
      {:ok, other_tag} = Tags.create_tag(%{name: "other"})
      assert {:ok, updated} = Tags.remove_tag_from_document(document, other_tag)
      updated = Repo.preload(updated, :tags)
      assert length(updated.tags) == 1
    end
  end
end
