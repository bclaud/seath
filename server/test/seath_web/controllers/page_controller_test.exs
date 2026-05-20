defmodule SeathWeb.PageControllerTest do
  use SeathWeb.ConnCase

  test "GET / returns dashboard", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Seath"
  end
end
