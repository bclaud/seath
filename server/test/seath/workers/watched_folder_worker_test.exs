defmodule Seath.Workers.WatchedFolderWorkerTest do
  use Seath.DataCase

  alias Seath.Workers.WatchedFolderWorker

  @test_watch_dir "test/tmp/watched"
  @test_processed_dir "test/tmp/watched/processed"
  @test_upload_dir "test/tmp/uploads"

  setup do
    Application.put_env(:seath, :watched_folder,
      path: @test_watch_dir,
      processed_subdir: "processed",
      allowed_extensions: ~w(.pdf .png .jpg .jpeg .tiff .txt)
    )

    Application.put_env(:seath, :storage, upload_dir: @test_upload_dir)

    File.mkdir_p!(@test_watch_dir)
    File.mkdir_p!(@test_upload_dir)

    on_exit(fn ->
      if File.exists?("test/tmp"), do: File.rm_rf!("test/tmp")
      Application.put_env(:seath, :watched_folder, path: "priv/watched")
      Application.put_env(:seath, :storage, upload_dir: "priv/uploads")
    end)

    :ok
  end

  describe "perform/1" do
    test "ingests a PDF file and moves it to processed" do
      source = Path.join(@test_watch_dir, "report.pdf")
      File.write!(source, "fake pdf content")

      assert {:ok, count} = WatchedFolderWorker.perform(%Oban.Job{})
      assert count == 1
      refute File.exists?(source)
      assert File.exists?(Path.join(@test_processed_dir, "report.pdf"))
    end

    test "processes multiple files" do
      for {name, content} <- [{"a.pdf", "content a"}, {"b.pdf", "content b"}, {"c.png", "content c"}] do
        File.write!(Path.join(@test_watch_dir, name), content)
      end

      assert {:ok, count} = WatchedFolderWorker.perform(%Oban.Job{})
      assert count == 3

      for name <- ~w(a.pdf b.pdf c.png) do
        assert File.exists?(Path.join(@test_processed_dir, name))
      end
    end

    test "skips unsupported file extensions" do
      File.write!(Path.join(@test_watch_dir, "script.sh"), "echo hi")
      File.write!(Path.join(@test_watch_dir, "readme.md"), "# Readme")

      assert {:ok, count} = WatchedFolderWorker.perform(%Oban.Job{})
      assert count == 0
    end

    test "handles empty watch directory" do
      assert {:ok, 0} = WatchedFolderWorker.perform(%Oban.Job{})
    end

    test "handles missing watch directory" do
      File.rm_rf!(@test_watch_dir)
      assert {:ok, 0} = WatchedFolderWorker.perform(%Oban.Job{})
    end

    test "skips subdirectories in the watch folder" do
      File.mkdir_p!(Path.join(@test_watch_dir, "subdir"))
      File.write!(Path.join(@test_watch_dir, "doc.pdf"), "content")

      assert {:ok, count} = WatchedFolderWorker.perform(%Oban.Job{})
      assert count == 1
    end

    test "ingests multiple file types" do
      for {name, content} <- [{"scan.pdf", "pdf content"}, {"photo.jpg", "jpg content"}, {"note.txt", "txt content"}] do
        File.write!(Path.join(@test_watch_dir, name), content)
      end

      assert {:ok, count} = WatchedFolderWorker.perform(%Oban.Job{})
      assert count == 3
    end
  end
end
