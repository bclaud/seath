defmodule Seath.StorageTest do
  use ExUnit.Case, async: true

  alias Seath.Storage

  @test_upload_dir "test/tmp/uploads"

  setup do
    # Override the upload dir for tests
    Application.put_env(:seath, :storage, upload_dir: @test_upload_dir)

    on_exit(fn ->
      # Clean up test upload directory
      if File.exists?(@test_upload_dir) do
        File.rm_rf!(@test_upload_dir)
      end

      # Restore original config
      Application.put_env(:seath, :storage, upload_dir: "priv/uploads")
    end)

    :ok
  end

  describe "upload_dir/0" do
    test "returns the configured upload directory" do
      assert Storage.upload_dir() == @test_upload_dir
    end
  end

  describe "store/2" do
    test "stores a file and returns the stored path" do
      temp_path = create_temp_file("hello world", ".txt")

      assert {:ok, stored_path} = Storage.store(temp_path, "document.txt")
      assert File.exists?(stored_path)
      assert String.starts_with?(stored_path, @test_upload_dir)
      assert File.read!(stored_path) == "hello world"
    end

    test "generates a unique filename with UUID and original extension" do
      temp_path = create_temp_file("content", ".pdf")

      assert {:ok, stored_path} = Storage.store(temp_path, "report.pdf")
      filename = Path.basename(stored_path)
      assert String.ends_with?(filename, ".pdf")
      # UUIDs are 36 chars, so filename should be 36 + 4 (.pdf) = 40
      assert String.length(filename) == 40
    end

    test "each call generates a different filename" do
      temp_path = create_temp_file("content", ".pdf")

      assert {:ok, path1} = Storage.store(temp_path, "report.pdf")
      assert {:ok, path2} = Storage.store(temp_path, "report.pdf")
      assert path1 != path2
    end

    test "creates the upload directory if it does not exist" do
      # Ensure directory doesn't exist yet
      if File.exists?(@test_upload_dir), do: File.rm_rf!(@test_upload_dir)
      refute File.exists?(@test_upload_dir)

      temp_path = create_temp_file("data", ".txt")
      assert {:ok, _stored_path} = Storage.store(temp_path, "doc.txt")
      assert File.exists?(@test_upload_dir)
    end
  end

  describe "delete/1" do
    test "deletes an existing file" do
      temp_path = create_temp_file("to delete", ".txt")
      {:ok, stored_path} = Storage.store(temp_path, "delete_me.txt")
      assert File.exists?(stored_path)

      assert :ok = Storage.delete(stored_path)
      refute File.exists?(stored_path)
    end

    test "returns error when file does not exist" do
      assert {:error, reason} = Storage.delete("/nonexistent/path/file.txt")
      assert reason =~ "file not found"
    end
  end

  # --- Helpers ---

  defp create_temp_file(content, extension) do
    tmp_dir = System.tmp_dir!()
    path = Path.join(tmp_dir, "seath_test_#{Ecto.UUID.generate()}#{extension}")
    File.write!(path, content)

    on_exit(fn ->
      if File.exists?(path), do: File.rm(path)
    end)

    path
  end
end
