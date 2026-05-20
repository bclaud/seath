defmodule SeathWeb.ChatLiveTest do
  use SeathWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders chat page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/chat")
    assert html =~ "Document Chat"
    assert html =~ "Ask a question about your documents"
  end

  test "submits a query and shows user message", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element("#chat-form")
    |> render_submit(%{query: "What is in my documents?"})

    assert render(view) =~ "What is in my documents?"
  end

  test "shows empty state when no messages", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/chat")
    assert html =~ "hero-chat-bubble-left-right"
  end
end
