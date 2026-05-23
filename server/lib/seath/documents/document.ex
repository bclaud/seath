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
          content_hash: String.t() | nil,
          ocr_text: String.t() | nil,
          status: String.t(),
          archived_at: DateTime.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @valid_statuses ~w(pending processing awaiting_review archived rejected error)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "documents" do
    field :title, :string
    field :file_path, :string
    field :file_name, :string
    field :file_type, :string
    field :file_size, :integer
    field :content_hash, :string
    field :ocr_text, :string
    field :confidence, :float
    field :error_message, :string
    field :status, :string, default: "pending"
    field :archived_at, :utc_datetime
    field :llm_reasoning, :string
    field :verification_data, :map, default: %{}
    field :classification_attempts, :integer, default: 0

    belongs_to :document_type, Seath.DocumentTypes.DocumentType
    belongs_to :correspondent, Seath.Correspondents.Correspondent
    many_to_many :tags, Seath.Tags.Tag, join_through: "document_tags", on_replace: :delete
    has_many :involved_parties, Seath.InvolvedParties.InvolvedParty

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
      :content_hash,
      :ocr_text,
      :confidence,
      :error_message,
      :status,
      :archived_at,
      :document_type_id,
      :correspondent_id,
      :llm_reasoning,
      :verification_data,
      :classification_attempts
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
      {"pending", "error"} -> :ok
      {"processing", "awaiting_review"} -> :ok
      {"processing", "error"} -> :ok
      {"awaiting_review", "archived"} -> :ok
      {"awaiting_review", "rejected"} -> :ok
      {"awaiting_review", "error"} -> :ok
      {"rejected", "pending"} -> :ok
      {"error", "pending"} -> :ok
      _ -> {:error, "invalid transition from #{current_status} to #{new_status}"}
    end
  end
end
