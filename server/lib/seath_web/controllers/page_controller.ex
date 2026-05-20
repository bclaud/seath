defmodule SeathWeb.PageController do
  use SeathWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
