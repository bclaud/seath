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
  Builds a YAML-like metadata header for a document's OCR text file.

  Includes: title, tags, document_type, correspondent, date, status,
  and involved parties. The header is separated from the body by `---`.
  """
  def build_metadata_header(%Document{} = document) do
    doc = Repo.preload(document, [:tags, :document_type, :correspondent])

    tags_str =
      doc.tags
      |> Enum.map(& &1.name)
      |> Enum.join(", ")

    type_name = doc.document_type && doc.document_type.name
    corr_name = doc.correspondent && doc.correspondent.name

    date_str =
      doc.inserted_at |> DateTime.to_naive() |> NaiveDateTime.to_date() |> Date.to_string()

    header = """
    title: #{doc.title || ""}
    tags: #{tags_str}
    document_type: #{type_name || ""}
    correspondent: #{corr_name || ""}
    date: #{date_str}
    status: #{doc.status}
    ---
    """

    header
  end

  @doc """
  Builds the full content for a document's OCR text file, including
  the metadata header followed by the OCR body text.
  """
  def build_text_file_content(%Document{} = document) do
    header = build_metadata_header(document)
    body = document.ocr_text || ""
    header <> body
  end

  @doc """
  Regenerates the OCR text file for a document.

  This is called when document metadata changes (tags, type, etc.)
  to keep the text file in sync with the database.

  Returns `{:ok, text_path}` or `{:error, reason}`.
  """
  def regenerate_text_file(%Document{} = document) do
    content = build_text_file_content(document)
    Storage.store_ocr_text(document.id, content)
  end

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
  Gets multiple documents by their ids.

  Returns a list of documents (empty list if none found).
  """
  def get_documents_by_ids(ids) when is_list(ids) do
    Repo.all(from d in Document, where: d.id in ^ids)
  end

  def get_documents_by_ids(_), do: []

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
  Updates a document and regenerates the OCR text file if metadata changed.

  Metadata fields that trigger regeneration: title, tags, document_type,
  correspondent, status. The `.txt` file is kept in sync with the database.
  """
  def update_document(%Document{} = document, attrs) do
    case document |> Document.changeset(attrs) |> Repo.update() do
      {:ok, updated} ->
        # Regenerate text file if metadata has changed and OCR text exists
        if updated.ocr_text && updated.ocr_text != "" do
          metadata_keys = ~w(title document_type_id correspondent_id status)a

          if has_metadata_changes?(document, updated, metadata_keys) do
            regenerate_text_file(updated)
          end
        end

        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Transitions a document to a new status using the state machine
  and regenerates the OCR text file if OCR text exists.
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

        case document |> Document.changeset(update_attrs) |> Repo.update() do
          {:ok, updated} ->
            if updated.ocr_text && updated.ocr_text != "" do
              regenerate_text_file(updated)
            end

            {:ok, updated}

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Stores OCR text for a document, transitions it to processing,
  and writes the text file (with metadata header) to disk.

  The text file is stored at `{upload_dir}/{document_id}/{document_id}.txt`
  with a YAML-like metadata header for grep-based retrieval.
  """
  def store_ocr_text(%Document{} = document, ocr_text) do
    with {:ok, updated} <-
           document
           |> Document.changeset(%{ocr_text: ocr_text, status: "processing"})
           |> Repo.update() do
      # Write the text file with metadata header alongside the original document
      content = build_text_file_content(updated)
      Storage.store_ocr_text(document.id, content)
      {:ok, updated}
    end
  end

  @doc """
  Marks a document as errored with a descriptive message.
  The document can be retried later (error -> pending).
  """
  def mark_as_error(%Document{} = document, message) do
    document
    |> Document.changeset(%{status: "error", error_message: message})
    |> Repo.update()
  end

  @doc """
  Resets an errored document back to pending for retry.
  """
  def retry(%Document{} = document) do
    document
    |> Document.changeset(%{status: "pending", error_message: nil})
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
  Returns paginated documents with optional filtering, sorting, and search.

  Supports filters: status, tag_ids, document_type_id, correspondent_id,
  date_from, date_to, and full-text search query.

  Returns `{documents, total_count}`.
  """
  def list_documents_paginated(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    per_page = Keyword.get(opts, :per_page, 20)
    sort_by = Keyword.get(opts, :sort_by, "inserted_at")
    sort_order = Keyword.get(opts, :sort_order, :desc)
    search_query = Keyword.get(opts, :search)
    status = Keyword.get(opts, :status)
    tag_ids = Keyword.get(opts, :tag_ids)
    document_type_id = Keyword.get(opts, :document_type_id)
    correspondent_id = Keyword.get(opts, :correspondent_id)
    involved_party_name = Keyword.get(opts, :involved_party_name)
    date_from = Keyword.get(opts, :date_from)
    date_to = Keyword.get(opts, :date_to)

    base_query = from(d in Document, preload: [:tags, :document_type, :correspondent])

    base_query = maybe_filter_by_search(base_query, search_query)
    base_query = maybe_filter_by_status(base_query, status)
    base_query = maybe_filter_by_tags(base_query, tag_ids)
    base_query = maybe_filter_by_document_type(base_query, document_type_id)
    base_query = maybe_filter_by_correspondent(base_query, correspondent_id)
    base_query = maybe_filter_by_involved_party(base_query, involved_party_name)
    base_query = maybe_filter_by_date_range(base_query, date_from, date_to)

    sort_field = valid_sort_field(sort_by)
    ordered_query = from(d in base_query, order_by: [{^sort_order, field(d, ^sort_field)}])

    offset = (page - 1) * per_page

    documents =
      ordered_query
      |> offset(^offset)
      |> limit(^per_page)
      |> Repo.all()

    total_count =
      base_query
      |> Repo.aggregate(:count, :id)

    {documents, total_count}
  end

  @doc """
  Returns the 5 most recently uploaded documents.
  """
  def list_recent_documents(limit \\ 5) do
    Document
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload([:tags, :document_type, :correspondent])
    |> Repo.all()
  end

  # --- Filter helpers ---

  defp maybe_filter_by_search(query, nil), do: query
  defp maybe_filter_by_search(query, ""), do: query

  defp maybe_filter_by_search(query, search_query) do
    tsquery =
      search_query
      |> String.split()
      |> Enum.map(&(&1 <> ":*"))
      |> Enum.join(" & ")

    from(d in query,
      where:
        fragment("search_vector @@ to_tsquery('english', ?)", ^tsquery) or
          ilike(d.title, ^"%#{search_query}%") or
          ilike(d.file_name, ^"%#{search_query}%")
    )
  end

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, ""), do: query

  defp maybe_filter_by_status(query, status) do
    from(d in query, where: d.status == ^status)
  end

  defp maybe_filter_by_tags(query, nil), do: query
  defp maybe_filter_by_tags(query, []), do: query

  defp maybe_filter_by_tags(query, tag_ids) when is_list(tag_ids) do
    from(d in query,
      join: dt in "document_tags",
      on: dt.document_id == d.id,
      where: dt.tag_id in ^tag_ids,
      distinct: d.id
    )
  end

  defp maybe_filter_by_document_type(query, nil), do: query
  defp maybe_filter_by_document_type(query, ""), do: query

  defp maybe_filter_by_document_type(query, document_type_id) do
    from(d in query, where: d.document_type_id == ^document_type_id)
  end

  defp maybe_filter_by_correspondent(query, nil), do: query
  defp maybe_filter_by_correspondent(query, ""), do: query

  defp maybe_filter_by_correspondent(query, correspondent_id) do
    from(d in query, where: d.correspondent_id == ^correspondent_id)
  end

  defp maybe_filter_by_involved_party(query, nil), do: query
  defp maybe_filter_by_involved_party(query, ""), do: query

  defp maybe_filter_by_involved_party(query, name) do
    from(d in query,
      join: ip in assoc(d, :involved_parties),
      where: ilike(ip.name, ^"%#{name}%"),
      distinct: d.id
    )
  end

  defp maybe_filter_by_date_range(query, nil, nil), do: query

  defp maybe_filter_by_date_range(query, from, nil) when not is_nil(from) do
    from(d in query, where: d.inserted_at >= ^from)
  end

  defp maybe_filter_by_date_range(query, nil, to) when not is_nil(to) do
    from(d in query, where: d.inserted_at <= ^to)
  end

  defp maybe_filter_by_date_range(query, from, to) do
    from(d in query, where: d.inserted_at >= ^from and d.inserted_at <= ^to)
  end

  defp valid_sort_field(field)
       when field in ~w(title document_type_id correspondent_id status inserted_at updated_at file_name file_size confidence),
       do: field

  defp valid_sort_field(_), do: :inserted_at

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

  # Checks if any of the given metadata keys changed between old and new document.
  defp has_metadata_changes?(old_doc, new_doc, keys) do
    Enum.any?(keys, fn key ->
      Map.get(old_doc, key) != Map.get(new_doc, key)
    end)
  end
end
