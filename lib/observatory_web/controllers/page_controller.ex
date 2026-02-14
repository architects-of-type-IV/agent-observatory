defmodule ObservatoryWeb.PageController do
  use ObservatoryWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
