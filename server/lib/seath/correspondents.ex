defmodule Seath.Correspondents do
  @moduledoc """
  The Correspondents context.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.Correspondents.Correspondent

  @doc """
  Returns the list of all correspondents.
  """
  def list_correspondents do
    Repo.all(Correspondent)
  end

  @doc """
  Gets a single correspondent by id.

  Raises `Ecto.NoResultsError` if the correspondent does not exist.
  """
  def get_correspondent!(id), do: Repo.get!(Correspondent, id)

  @doc """
  Gets a single correspondent by name.

  Returns `nil` if the correspondent does not exist.
  """
  def get_correspondent_by_name(name), do: Repo.get_by(Correspondent, name: name)

  @doc """
  Creates a correspondent.
  """
  def create_correspondent(attrs \\ %{}) do
    %Correspondent{}
    |> Correspondent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a correspondent.
  """
  def update_correspondent(%Correspondent{} = correspondent, attrs) do
    correspondent
    |> Correspondent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a correspondent.
  """
  def delete_correspondent(%Correspondent{} = correspondent) do
    Repo.delete(correspondent)
  end
end
