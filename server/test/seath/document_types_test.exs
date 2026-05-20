defmodule Seath.DocumentTypesTest do
  use Seath.DataCase

  alias Seath.DocumentTypes
  alias Seath.DocumentTypes.DocumentType

  @valid_attrs %{name: "invoice", description: "An invoice document"}
  @update_attrs %{name: "receipt", description: "A receipt document"}

  describe "list_types/0" do
    test "returns all document types" do
      {:ok, type1} = DocumentTypes.create_type(%{name: "type1"})
      {:ok, type2} = DocumentTypes.create_type(%{name: "type2"})

      types = DocumentTypes.list_types()
      assert length(types) == 2
      assert Enum.any?(types, &(&1.id == type1.id))
      assert Enum.any?(types, &(&1.id == type2.id))
    end

    test "returns empty list when no types exist" do
      assert DocumentTypes.list_types() == []
    end
  end

  describe "get_type!/1" do
    test "returns the document type with the given id" do
      {:ok, type} = DocumentTypes.create_type(@valid_attrs)
      assert DocumentTypes.get_type!(type.id).id == type.id
    end

    test "raises when document type does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        DocumentTypes.get_type!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_type/1" do
    test "creates a document type with valid attrs" do
      assert {:ok, %DocumentType{} = type} = DocumentTypes.create_type(@valid_attrs)
      assert type.name == "invoice"
      assert type.description == "An invoice document"
    end

    test "creates a document type without description" do
      assert {:ok, %DocumentType{} = type} = DocumentTypes.create_type(%{name: "minimal"})
      assert type.name == "minimal"
      assert type.description == nil
    end

    test "returns error when name is missing" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               DocumentTypes.create_type(%{description: "desc"})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error when name is not unique" do
      assert {:ok, _type} = DocumentTypes.create_type(@valid_attrs)
      assert {:error, %Ecto.Changeset{} = changeset} = DocumentTypes.create_type(@valid_attrs)
      assert errors_on(changeset).name
    end
  end

  describe "update_type/2" do
    setup do
      {:ok, type} = DocumentTypes.create_type(@valid_attrs)
      %{type: type}
    end

    test "updates document type attributes", %{type: type} do
      assert {:ok, updated} = DocumentTypes.update_type(type, @update_attrs)
      assert updated.name == "receipt"
      assert updated.description == "A receipt document"
    end

    test "returns error with invalid data", %{type: type} do
      assert {:error, %Ecto.Changeset{}} = DocumentTypes.update_type(type, %{name: nil})
    end

    test "returns error when name is not unique", %{type: type} do
      {:ok, _other} = DocumentTypes.create_type(%{name: "receipt"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               DocumentTypes.update_type(type, %{name: "receipt"})

      assert errors_on(changeset).name
    end
  end

  describe "delete_type/1" do
    test "deletes the document type" do
      {:ok, type} = DocumentTypes.create_type(@valid_attrs)
      assert {:ok, %DocumentType{}} = DocumentTypes.delete_type(type)
      assert_raise Ecto.NoResultsError, fn -> DocumentTypes.get_type!(type.id) end
    end
  end
end
