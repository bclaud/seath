defmodule Seath.Tags do
  @moduledoc """
  The Tags context.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.Tags.Tag
  alias Seath.Documents
  alias Seath.Documents.Document

  @doc """
  Returns the list of all tags.
  """
  def list_tags do
    Repo.all(Tag)
  end

  @doc """
  Gets a single tag by id.

  Raises `Ecto.NoResultsError` if the tag does not exist.
  """
  def get_tag!(id), do: Repo.get!(Tag, id)

  @doc """
  Gets a single tag by name.

  Returns `nil` if the tag does not exist.
  """
  def get_tag_by_name(name), do: Repo.get_by(Tag, name: name)

  @doc """
  Creates a tag.
  """
  def create_tag(attrs \\ %{}) do
    %Tag{}
    |> Tag.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a tag.
  """
  def update_tag(%Tag{} = tag, attrs) do
    tag
    |> Tag.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a tag.
  """
  def delete_tag(%Tag{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Adds a tag to a document and regenerates the text file.
  """
  def add_tag_to_document(%Document{} = document, %Tag{} = tag) do
    document = Repo.preload(document, :tags)

    tags =
      if Enum.any?(document.tags, &(&1.id == tag.id)) do
        document.tags
      else
        document.tags ++ [tag]
      end

    case document
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.put_assoc(:tags, tags)
         |> Repo.update() do
      {:ok, updated} ->
        if updated.ocr_text && updated.ocr_text != "" do
          Documents.regenerate_text_file(updated)
        end

        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  Removes a tag from a document and regenerates the text file.
  """
  def remove_tag_from_document(%Document{} = document, %Tag{} = tag) do
    document = Repo.preload(document, :tags)

    case document
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.put_assoc(:tags, Enum.reject(document.tags, &(&1.id == tag.id)))
         |> Repo.update() do
      {:ok, updated} ->
        if updated.ocr_text && updated.ocr_text != "" do
          Documents.regenerate_text_file(updated)
        end

        {:ok, updated}

      error ->
        error
    end
  end
end
