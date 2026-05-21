defmodule Seath.Storage do
  @moduledoc """
  Handles local filesystem storage for uploaded documents and OCR text files.

  Document files are stored in the configured upload directory (default: `priv/uploads/`)
  with unique filenames generated from UUID + original extension.

  OCR text files are stored alongside documents in a per-document subdirectory:
  `{upload_dir}/{document_id}/{document_id}.txt`
  """

  @doc """
  Stores a file from a temp path to the upload directory.

  Returns `{:ok, stored_path}` or `{:error, reason}`.
  """
  @spec store(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store(temp_path, original_filename) do
    ext = Path.extname(original_filename)
    unique_name = Ecto.UUID.generate() <> ext
    dest_dir = upload_dir()
    dest_path = Path.join(dest_dir, unique_name)

    with :ok <- ensure_upload_dir(dest_dir),
         :ok <- copy_file(temp_path, dest_path) do
      {:ok, dest_path}
    end
  end

  @doc """
  Deletes a stored file from the upload directory.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec delete(String.t()) :: :ok | {:error, String.t()}
  def delete(file_path) do
    if File.exists?(file_path) do
      File.rm(file_path)
    else
      {:error, "file not found: #{file_path}"}
    end
  end

  @doc """
  Returns the configured upload directory path.

  Defaults to `priv/uploads/` relative to the application root.
  """
  @spec upload_dir() :: String.t()
  def upload_dir do
    Application.get_env(:seath, :storage)[:upload_dir] || "priv/uploads"
  end

  @doc """
  Returns the directory path for a document's auxiliary files.

  Documents get their own subdirectory for OCR text files and other extras:
  `{upload_dir}/{document_id}/`
  """
  @spec document_dir(String.t()) :: String.t()
  def document_dir(document_id) do
    Path.join([upload_dir(), document_id])
  end

  @doc """
  Returns the path to a document's OCR text file.

  The file is stored at `{document_dir(document_id)}/{document_id}.txt`.
  """
  @spec ocr_text_path(String.t()) :: String.t()
  def ocr_text_path(document_id) do
    Path.join(document_dir(document_id), "#{document_id}.txt")
  end

  @doc """
  Stores OCR text for a document as a plain text file.

  Writes the content (with a metadata header if provided) to
  `{document_dir(document_id)}/{document_id}.txt`.

  Returns `{:ok, text_path}` or `{:error, reason}`.
  """
  @spec store_ocr_text(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def store_ocr_text(document_id, content) do
    doc_dir = document_dir(document_id)
    text_path = ocr_text_path(document_id)

    with :ok <- ensure_upload_dir(doc_dir),
         :ok <- File.write(text_path, content) do
      {:ok, text_path}
    end
  end

  @doc """
  Deletes the OCR text file for a document, if it exists.
  """
  @spec delete_ocr_text(String.t()) :: :ok
  def delete_ocr_text(document_id) do
    text_path = ocr_text_path(document_id)

    if File.exists?(text_path) do
      File.rm(text_path)
    else
      :ok
    end
  end

  # Ensures the upload directory exists, creating it if necessary.
  defp ensure_upload_dir(dir) do
    if File.exists?(dir) do
      :ok
    else
      case File.mkdir_p(dir) do
        :ok -> :ok
        {:error, reason} -> {:error, "failed to create upload directory: #{reason}"}
      end
    end
  end

  # Copies a file from source to destination.
  defp copy_file(src, dest) do
    case File.cp(src, dest) do
      :ok -> :ok
      {:error, reason} -> {:error, "failed to copy file: #{reason}"}
    end
  end
end
