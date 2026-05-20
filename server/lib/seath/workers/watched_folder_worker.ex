defmodule Seath.Workers.WatchedFolderWorker do
  use Oban.Worker, queue: :ingest, max_attempts: 3, unique: [period: :infinity]

  @impl Oban.Worker
  def perform(_job) do
    config = Application.get_env(:seath, :watched_folder, [])
    watch_dir = Keyword.get(config, :path, "priv/watched")
    processed_dir = Keyword.get(config, :processed_subdir, "processed")
    allowed = Keyword.get(config, :allowed_extensions, ~w(.pdf .png .jpg .jpeg .tiff .txt))

    watch_path = Path.absname(watch_dir)
    processed_path = Path.join(watch_path, processed_dir)
    File.mkdir_p!(processed_path)

    case File.ls(watch_path) do
      {:ok, entries} ->
        files =
          Enum.filter(entries, fn f ->
            path = Path.join(watch_path, f)
            not File.dir?(path) and String.downcase(Path.extname(f)) in allowed
          end)

        Enum.each(files, fn filename ->
          source = Path.join(watch_path, filename)
          target = Path.join(processed_path, filename)

          case Seath.Documents.ingest(source, filename) do
            {:ok, _doc} -> File.rename!(source, target)
            {:error, _} -> :ok
          end
        end)

        {:ok, length(files)}

      {:error, _} ->
        {:ok, 0}
    end
  end
end
