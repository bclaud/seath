defmodule SeathWeb.DocumentController do
  use SeathWeb, :controller

  @thumb_dir "priv/static/uploads/thumbnails"
  @thumb_width 200

  def thumbnail(conn, %{"id" => id}) do
    doc = Seath.Documents.get_document!(id)
    thumb_path = thumbnail_path(doc)

    if File.exists?(thumb_path) do
      send_file(conn, 200, thumb_path)
    else
      # Generate thumbnail
      case generate_thumbnail(doc, thumb_path) do
        :ok ->
          send_file(conn, 200, thumb_path)

        {:error, reason} ->
          conn
          |> put_status(404)
          |> json(%{error: reason})
      end
    end
  end

  defp thumbnail_path(doc) do
    ext =
      case doc.file_type do
        "application/pdf" -> ".png"
        "image/png" -> ".png"
        "image/jpeg" -> ".jpg"
        _ -> ".png"
      end

    Path.join(@thumb_dir, "#{doc.id}#{ext}")
  end

  defp generate_thumbnail(doc, thumb_path) do
    # Ensure thumbnails directory exists
    File.mkdir_p!(@thumb_dir)

    full_path = Path.join(File.cwd!(), doc.file_path)

    case doc.file_type do
      "application/pdf" ->
        generate_pdf_thumbnail(full_path, thumb_path)

      _image_type ->
        generate_image_thumbnail(full_path, thumb_path)
    end
  end

  defp generate_pdf_thumbnail(pdf_path, thumb_path) do
    tmp = Path.rootname(thumb_path, ".png")

    case System.cmd("pdftoppm", [
           "-png",
           "-r",
           "72",
           "-f",
           "1",
           "-singlefile",
           pdf_path,
           tmp
         ]) do
      {_output, 0} ->
        # pdftoppm outputs to tmp.png, rename if needed
        generated = tmp <> ".png"

        if File.exists?(generated) and generated != thumb_path do
          File.rename(generated, thumb_path)
        end

        :ok

      {_output, exit_code} ->
        {:error, "pdftoppm failed with exit code #{exit_code}"}
    end
  rescue
    e ->
      {:error, "Failed to generate PDF thumbnail: #{Exception.message(e)}"}
  end

  defp generate_image_thumbnail(image_path, thumb_path) do
    # Use ImageMagick's convert if available, otherwise just copy
    case System.cmd("convert", [
           image_path,
           "-resize",
           "#{@thumb_width}x",
           thumb_path
         ]) do
      {_output, 0} ->
        :ok

      {_output, _exit_code} ->
        # Fallback: just copy the file
        File.cp(image_path, thumb_path)
    end
  rescue
    _ ->
      # Fallback: just copy the file
      File.cp(image_path, thumb_path)
  end
end
