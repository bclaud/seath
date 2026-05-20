defmodule Seath.CorrespondentsTest do
  use Seath.DataCase

  alias Seath.Correspondents
  alias Seath.Correspondents.Correspondent

  @valid_attrs %{name: "Acme Corp", color: "#FF5733"}
  @update_attrs %{name: "Globex Inc", color: "#33FF57"}

  describe "list_correspondents/0" do
    test "returns all correspondents" do
      {:ok, c1} = Correspondents.create_correspondent(%{name: "one"})
      {:ok, c2} = Correspondents.create_correspondent(%{name: "two"})

      correspondents = Correspondents.list_correspondents()
      assert length(correspondents) == 2
      assert Enum.any?(correspondents, &(&1.id == c1.id))
      assert Enum.any?(correspondents, &(&1.id == c2.id))
    end

    test "returns empty list when no correspondents exist" do
      assert Correspondents.list_correspondents() == []
    end
  end

  describe "get_correspondent!/1" do
    test "returns the correspondent with the given id" do
      {:ok, correspondent} = Correspondents.create_correspondent(@valid_attrs)
      assert Correspondents.get_correspondent!(correspondent.id).id == correspondent.id
    end

    test "raises when correspondent does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Correspondents.get_correspondent!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_correspondent_by_name/1" do
    test "returns correspondent by name" do
      {:ok, _} = Correspondents.create_correspondent(@valid_attrs)

      assert %Correspondent{name: "Acme Corp"} =
               Correspondents.get_correspondent_by_name("Acme Corp")
    end

    test "returns nil when name not found" do
      assert Correspondents.get_correspondent_by_name("nonexistent") == nil
    end
  end

  describe "create_correspondent/1" do
    test "creates a correspondent with valid attrs" do
      assert {:ok, %Correspondent{} = correspondent} =
               Correspondents.create_correspondent(@valid_attrs)

      assert correspondent.name == "Acme Corp"
      assert correspondent.color == "#FF5733"
    end

    test "creates a correspondent without color" do
      assert {:ok, %Correspondent{} = correspondent} =
               Correspondents.create_correspondent(%{name: "minimal"})

      assert correspondent.name == "minimal"
      assert correspondent.color == nil
    end

    test "returns error when name is missing" do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Correspondents.create_correspondent(%{color: "#000"})

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error when name is not unique" do
      assert {:ok, _} = Correspondents.create_correspondent(@valid_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Correspondents.create_correspondent(@valid_attrs)

      assert errors_on(changeset).name
    end
  end

  describe "update_correspondent/2" do
    setup do
      {:ok, correspondent} = Correspondents.create_correspondent(@valid_attrs)
      %{correspondent: correspondent}
    end

    test "updates correspondent attributes", %{correspondent: correspondent} do
      assert {:ok, updated} = Correspondents.update_correspondent(correspondent, @update_attrs)
      assert updated.name == "Globex Inc"
      assert updated.color == "#33FF57"
    end

    test "returns error with invalid data", %{correspondent: correspondent} do
      assert {:error, %Ecto.Changeset{}} =
               Correspondents.update_correspondent(correspondent, %{name: nil})
    end

    test "returns error when name is not unique", %{correspondent: correspondent} do
      {:ok, _other} = Correspondents.create_correspondent(%{name: "Globex Inc"})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Correspondents.update_correspondent(correspondent, %{name: "Globex Inc"})

      assert errors_on(changeset).name
    end
  end

  describe "delete_correspondent/1" do
    test "deletes the correspondent" do
      {:ok, correspondent} = Correspondents.create_correspondent(@valid_attrs)
      assert {:ok, %Correspondent{}} = Correspondents.delete_correspondent(correspondent)

      assert_raise Ecto.NoResultsError, fn ->
        Correspondents.get_correspondent!(correspondent.id)
      end
    end
  end
end
