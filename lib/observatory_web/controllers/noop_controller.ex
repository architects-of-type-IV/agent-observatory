defmodule ObservatoryWeb.NoopController do
  use ObservatoryWeb, :controller

  def noop(conn, _params), do: send_resp(conn, 204, "")
end
