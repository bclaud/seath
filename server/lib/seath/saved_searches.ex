defmodule Seath.SavedSearches do
  import Ecto.Query
  alias Seath.Repo

  def list_saved_searches do
    Repo.all(Seath.SavedSearches.SavedSearch)
  end

  def get_saved_search!(id), do: Repo.get!(Seath.SavedSearches.SavedSearch, id)

  def create_saved_search(attrs) do
    %Seath.SavedSearches.SavedSearch{}
    |> Seath.SavedSearches.SavedSearch.changeset(attrs)
    |> Repo.insert()
  end

  def update_saved_search(search, attrs) do
    search
    |> Seath.SavedSearches.SavedSearch.changeset(attrs)
    |> Repo.update()
  end

  def delete_saved_search(search), do: Repo.delete(search)
end
