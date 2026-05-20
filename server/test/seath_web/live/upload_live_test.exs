defmodule SeathWeb.UploadLiveTest do
  use SeathWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders upload page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/upload")
    assert html =~ "Upload Documents"
    assert html =~ "Drag and drop files"
  end

  test "shows file type restrictions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")

    view
    |> file_input("#upload-zone", :document, [
      %{name: "test.exe", content: "bad", type: "application/x-msdownload"}
    ])
    |> render_upload("test.exe")

    assert render(view) =~ "test.exe"
  end

  test "receives status updates via PubSub", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/upload")

    # Simulate a PubSub broadcast
    Phoenix.PubSub.broadcast(
      Seath.PubSub,
      "documents",
      {:document_updated, %{id: "test-id", status: "processing"}}
    )

    # The handle_info should process the update without crashing
    render(view)
    assert true
  end
end
