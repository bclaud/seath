defmodule Seath.Storage do
  @moduledoc """
  Handles local filesystem storage for uploaded documents.

  Files are stored in the configured upload directory (default: `priv/uploads/`)
  with unique filenames generated from UUID + original extension.
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
