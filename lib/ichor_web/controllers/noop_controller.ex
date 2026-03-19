defmodule IchorWeb.NoopController do
  @moduledoc "Silences browser probe requests (e.g. Chrome DevTools well-known paths) with HTTP 204."

  use IchorWeb, :controller

  def noop(conn, _params), do: send_resp(conn, 204, "")
end
