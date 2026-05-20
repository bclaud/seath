defmodule Seath.SavedSearchesTest do
  use Seath.DataCase

  alias Seath.SavedSearches

  @valid_attrs %{name: "Invoices"}
  @invalid_attrs %{name: nil}

  test "list_saved_searches/0 returns all saved searches" do
    SavedSearches.create_saved_search(@valid_attrs)
    assert length(SavedSearches.list_saved_searches()) == 1
  end

  test "get_saved_search!/1 returns the search with given id" do
    {:ok, search} = SavedSearches.create_saved_search(@valid_attrs)
    assert SavedSearches.get_saved_search!(search.id).name == "Invoices"
  end

  test "create_saved_search/1 with valid data creates a search" do
    {:ok, search} = SavedSearches.create_saved_search(@valid_attrs)
    assert search.name == "Invoices"
  end

  test "create_saved_search/1 with invalid data returns error" do
    assert {:error, _} = SavedSearches.create_saved_search(@invalid_attrs)
  end

  test "update_saved_search/2 updates the search" do
    {:ok, search} = SavedSearches.create_saved_search(@valid_attrs)
    {:ok, updated} = SavedSearches.update_saved_search(search, %{name: "Receipts"})
    assert updated.name == "Receipts"
  end

  test "delete_saved_search/1 deletes the search" do
    {:ok, search} = SavedSearches.create_saved_search(@valid_attrs)
    SavedSearches.delete_saved_search(search)
    assert SavedSearches.list_saved_searches() == []
  end
end
