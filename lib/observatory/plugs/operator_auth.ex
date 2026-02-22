defmodule Observatory.Plugs.OperatorAuth do
  @moduledoc """
  Plug that extracts and validates the `x-observatory-operator-id` header.

  Assigns `:operator_id` on the connection or halts with 401 if missing/empty.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn |> get_req_header("x-observatory-operator-id") |> List.first() do
      nil ->
        conn |> put_status(401) |> json(%{status: "error", reason: "missing_operator_id"}) |> halt()

      value ->
        trimmed = String.trim(value)

        if trimmed == "" do
          conn |> put_status(401) |> json(%{status: "error", reason: "missing_operator_id"}) |> halt()
        else
          assign(conn, :operator_id, trimmed)
        end
    end
  end
end
