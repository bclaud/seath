defmodule SeathWeb.ChatLiveTest do
  use SeathWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders chat page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/chat")
    assert html =~ "Document Chat"
    assert html =~ "Ask a question about your documents"
  end

  test "submits a query and streams a response", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element("#chat-form")
    |> render_submit(%{query: "What is in my documents?"})

    # User message appears immediately
    assert render(view) =~ "What is in my documents?"

    # Wait for the async streaming task to complete
    assert wait_for_async(view, 500, fn html ->
             String.contains?(html, "mock")
           end)
  end

  test "shows empty state when no messages", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/chat")
    assert html =~ "hero-chat-bubble-left-right"
  end

  defp wait_for_async(_view, 0, _assertion_fn), do: false

  defp wait_for_async(view, remaining_ms, assertion_fn) do
    html = render(view)

    if assertion_fn.(html) do
      true
    else
      Process.sleep(50)
      wait_for_async(view, remaining_ms - 50, assertion_fn)
    end
  end
end
