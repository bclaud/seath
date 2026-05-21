defmodule Seath.InvolvedParties.InvolvedParty do
  @moduledoc """
  Represents a person or entity mentioned in a document.

  Unlike the single `correspondent` field, involved parties capture
  all named entities (people, companies, organizations) that appear
  in a document, each with a role describing their relationship.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          document_id: Ecto.UUID.t(),
          name: String.t(),
          role: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "involved_parties" do
    field :name, :string
    field :role, :string

    belongs_to :document, Seath.Documents.Document

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an involved party.
  """
  def changeset(involved_party, attrs) do
    involved_party
    |> cast(attrs, [:document_id, :name, :role])
    |> validate_required([:document_id, :name])
    |> foreign_key_constraint(:document_id)
  end
end
