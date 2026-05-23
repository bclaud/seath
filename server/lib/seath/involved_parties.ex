defmodule Seath.InvolvedParties do
  @moduledoc """
  The InvolvedParties context.

  Manages named entities (people, companies, organizations) extracted
  from documents, each with a role describing their relationship.

  Unlike the single `correspondent` field on documents, involved parties
  support multiple entities per document — critical for contracts,
  emails, and legal documents that mention many parties.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.InvolvedParties.InvolvedParty

  @doc """
  Returns the list of all involved parties.
  """
  def list_involved_parties do
    Repo.all(InvolvedParty)
  end

  @doc """
  Gets a single involved party by id.

  Raises `Ecto.NoResultsError` if the party does not exist.
  """
  def get_involved_party!(id), do: Repo.get!(InvolvedParty, id)

  @doc """
  Gets all involved parties for a given document.
  """
  def list_parties_by_document(document_id) do
    Repo.all(from ip in InvolvedParty, where: ip.document_id == ^document_id)
  end

  @doc """
  Deletes all involved parties for a given document.
  Used when purging a document from the system.
  """
  def delete_for_document(document_id) do
    from(ip in InvolvedParty, where: ip.document_id == ^document_id)
    |> Repo.delete_all()
  end

  @doc """
  Creates an involved party.
  """
  def create_involved_party(attrs \\ %{}) do
    %InvolvedParty{}
    |> InvolvedParty.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an involved party.
  """
  def update_involved_party(%InvolvedParty{} = involved_party, attrs) do
    involved_party
    |> InvolvedParty.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an involved party.
  """
  def delete_involved_party(%InvolvedParty{} = involved_party) do
    Repo.delete(involved_party)
  end

  @doc """
  Bulk replaces all involved parties for a document.

  Deletes all existing parties and inserts the new ones in a single transaction.
  Each entry should be a map with `:name` and optional `:role` keys.
  """
  def replace_parties_for_document(document_id, parties) do
    Repo.transaction(fn ->
      # Delete existing parties
      from(ip in InvolvedParty, where: ip.document_id == ^document_id)
      |> Repo.delete_all()

      # Insert new parties
      Enum.each(parties, fn attrs ->
        %InvolvedParty{}
        |> InvolvedParty.changeset(Map.put(attrs, :document_id, document_id))
        |> Repo.insert!()
      end)
    end)
  end

  @doc """
  Searches involved parties by name (case-insensitive).
  """
  def search_by_name(name_query) do
    Repo.all(
      from ip in InvolvedParty,
        where: ilike(ip.name, ^"%#{name_query}%"),
        preload: [:document]
    )
  end
end
