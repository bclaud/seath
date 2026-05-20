defmodule Seath.ArchiveRules.ArchivalRule do
  @moduledoc """
  Schema representing a tag-based archival rule.

  An archival rule automatically transitions documents with a given tag
  to a target status (e.g. "archived" or "rejected") once they exceed
  a specified age in days.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          name: String.t(),
          tag_id: Ecto.UUID.t(),
          tag: Seath.Tags.Tag.t() | Ecto.Association.NotLoaded.t(),
          age_days: integer(),
          target_status: String.t(),
          enabled: boolean(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @valid_target_statuses ~w(archived rejected)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "archival_rules" do
    field :name, :string
    field :age_days, :integer, default: 90
    field :target_status, :string, default: "archived"
    field :enabled, :boolean, default: true
    belongs_to :tag, Seath.Tags.Tag

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for an archival rule.
  """
  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:name, :tag_id, :age_days, :target_status, :enabled])
    |> validate_required([:name, :tag_id, :age_days])
    |> validate_number(:age_days, greater_than: 0)
    |> validate_inclusion(:target_status, @valid_target_statuses)
    |> unique_constraint(:name)
  end
end
