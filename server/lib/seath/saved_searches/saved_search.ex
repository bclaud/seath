defmodule Seath.SavedSearches.SavedSearch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_searches" do
    field :name, :string
    field :query, :string
    field :tag_ids, {:array, :binary_id}
    field :status_filter, :string
    field :date_from, :date
    field :date_to, :date
    belongs_to :document_type, Seath.DocumentTypes.DocumentType

    timestamps()
  end

  def changeset(search, attrs) do
    search
    |> cast(attrs, [:name, :query, :tag_ids, :document_type_id, :status_filter, :date_from, :date_to])
    |> validate_required([:name])
  end
end
