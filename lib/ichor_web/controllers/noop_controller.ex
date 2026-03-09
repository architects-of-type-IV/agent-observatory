defmodule IchorWeb.NoopController do
  use IchorWeb, :controller

  def noop(conn, _params), do: send_resp(conn, 204, "")
end
