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

    html = render(view)
    assert html =~ "PDF, PNG, JPG"
    assert html =~ "up to 50MB"
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
