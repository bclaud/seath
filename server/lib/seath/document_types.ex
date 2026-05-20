defmodule Seath.DocumentTypes do
  @moduledoc """
  The DocumentTypes context.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.DocumentTypes.DocumentType

  @doc """
  Returns the list of all document types.
  """
  def list_types do
    Repo.all(DocumentType)
  end

  @doc """
  Gets a single document type by id.

  Raises `Ecto.NoResultsError` if the document type does not exist.
  """
  def get_type!(id), do: Repo.get!(DocumentType, id)

  @doc """
  Gets a single document type by name.

  Returns `nil` if the document type does not exist.
  """
  def get_type_by_name(name), do: Repo.get_by(DocumentType, name: name)

  @doc """
  Creates a document type.
  """
  def create_type(attrs \\ %{}) do
    %DocumentType{}
    |> DocumentType.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a document type.
  """
  def update_type(%DocumentType{} = document_type, attrs) do
    document_type
    |> DocumentType.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a document type.
  """
  def delete_type(%DocumentType{} = document_type) do
    Repo.delete(document_type)
  end
end
