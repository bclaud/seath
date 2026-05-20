defmodule Seath.Documents.Document do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          title: String.t() | nil,
          file_path: String.t(),
          file_name: String.t(),
          file_type: String.t(),
          file_size: integer(),
          ocr_text: String.t() | nil,
          status: String.t(),
          archived_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @valid_statuses ~w(pending processing awaiting_review archived rejected)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "documents" do
    field :title, :string
    field :file_path, :string
    field :file_name, :string
    field :file_type, :string
    field :file_size, :integer
    field :ocr_text, :string
    field :status, :string, default: "pending"
    field :archived_at, :utc_datetime

    belongs_to :document_type, Seath.DocumentTypes.DocumentType
    many_to_many :tags, Seath.Tags.Tag, join_through: "document_tags", on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a document.
  """
  def changeset(document, attrs) do
    document
    |> cast(attrs, [
      :title,
      :file_path,
      :file_name,
      :file_type,
      :file_size,
      :ocr_text,
      :status,
      :archived_at
    ])
    |> validate_required([:file_path, :file_name, :file_type, :file_size])
    |> validate_number(:file_size, greater_than: 0)
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Validates and applies a state transition.

  Allowed transitions:
    - pending → processing
    - processing → awaiting_review
    - awaiting_review → archived
    - awaiting_review → rejected
    - rejected → pending
  """
  def state_transition(current_status, new_status)

  def state_transition(current_status, new_status)
      when is_binary(current_status) and is_binary(new_status) do
    case {current_status, new_status} do
      {"pending", "processing"} -> :ok
      {"processing", "awaiting_review"} -> :ok
      {"awaiting_review", "archived"} -> :ok
      {"awaiting_review", "rejected"} -> :ok
      {"rejected", "pending"} -> :ok
      _ -> {:error, "invalid transition from #{current_status} to #{new_status}"}
    end
  end
end
