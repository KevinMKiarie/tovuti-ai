defmodule TovutiAiWeb.PageController do
  use TovutiAiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
