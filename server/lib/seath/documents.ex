defmodule Seath.Documents do
  @moduledoc """
  The Documents context.
  """

  import Ecto.Query, warn: false
  alias Seath.Repo
  alias Seath.Documents.Document
  alias Seath.Storage

  @max_file_size 50 * 1024 * 1024
  @allowed_extensions ~w(.pdf .png .jpg .jpeg .tiff .txt)

  @doc """
  Returns the list of all documents.
  """
  def list_documents do
    Repo.all(Document)
  end

  @doc """
  Returns the list of documents filtered by status.
  """
  def list_by_status(status) do
    Repo.all(from d in Document, where: d.status == ^status)
  end

  @doc """
  Gets a single document by id.

  Returns `nil` if the document does not exist.
  """
  def get_document(id), do: Repo.get(Document, id)

  @doc """
  Gets a single document by id.

  Raises `Ecto.NoResultsError` if the document does not exist.
  """
  def get_document!(id), do: Repo.get!(Document, id)

  @doc """
  Creates a document.
  """
  def create_document(attrs \\ %{}) do
    %Document{}
    |> Document.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Ingests a document from a temp file path.

  Validates file type and size, stores the file via `Seath.Storage`,
  and creates a Document record in `:pending` status.

  Returns `{:ok, document}` or `{:error, reason}`.
  """
  @spec ingest(String.t(), String.t()) ::
          {:ok, Document.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def ingest(temp_path, original_filename) do
    ext = Path.extname(original_filename) |> String.downcase()

    with :ok <- validate_extension(ext),
         {:ok, file_size} <- read_file_size(temp_path),
         :ok <- validate_file_size(file_size),
         {:ok, stored_path} <- Storage.store(temp_path, original_filename) do
      create_document(%{
        file_path: stored_path,
        file_name: original_filename,
        file_type: mime_type(ext),
        file_size: file_size,
        status: "pending"
      })
    end
  end

  @doc """
  Updates a document.
  """
  def update_document(%Document{} = document, attrs) do
    document
    |> Document.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Transitions a document to a new status using the state machine.
  """
  def transition_status(%Document{} = document, new_status) do
    case Document.state_transition(document.status, new_status) do
      :ok ->
        update_attrs =
          if new_status == "archived" do
            %{status: new_status, archived_at: DateTime.utc_now()}
          else
            %{status: new_status}
          end

        document
        |> Document.changeset(update_attrs)
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stores OCR text for a document and transitions it to processing.
  """
  def store_ocr_text(%Document{} = document, ocr_text) do
    document
    |> Document.changeset(%{ocr_text: ocr_text, status: "processing"})
    |> Repo.update()
  end

  @doc """
  Searches documents by full-text search over title, OCR text, and file name.

  Uses PostgreSQL tsvector/tsquery for ranked full-text search.
  Returns an empty list for empty or nil queries.
  """
  def search(query) when is_binary(query) and query != "" do
    tsquery =
      query
      |> String.split()
      |> Enum.map(&(&1 <> ":*"))
      |> Enum.join(" & ")

    from(d in Document,
      where: fragment("search_vector @@ to_tsquery('english', ?)", ^tsquery),
      order_by: fragment("ts_rank(search_vector, to_tsquery('english', ?)) DESC", ^tsquery),
      preload: [:tags, :document_type]
    )
    |> Repo.all()
  end

  def search(_), do: []

  @doc """
  Validates that a file size does not exceed the maximum allowed size.

  Returns `:ok` or `{:error, reason}`.
  """
  def validate_file_size(size) when is_integer(size) and size > 0 do
    if size <= @max_file_size do
      :ok
    else
      {:error, "file size exceeds maximum of 50MB"}
    end
  end

  # --- Private helpers ---

  defp validate_extension(ext) when ext in @allowed_extensions, do: :ok

  defp validate_extension(ext) do
    {:error, "unsupported file type: #{ext}"}
  end

  defp read_file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, "cannot read file: #{reason}"}
    end
  end

  defp mime_type(".pdf"), do: "application/pdf"
  defp mime_type(".png"), do: "image/png"
  defp mime_type(".jpg"), do: "image/jpeg"
  defp mime_type(".jpeg"), do: "image/jpeg"
  defp mime_type(".tiff"), do: "image/tiff"
  defp mime_type(".txt"), do: "text/plain"
  defp mime_type(_), do: "application/octet-stream"
end
