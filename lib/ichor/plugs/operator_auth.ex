defmodule Ichor.Plugs.OperatorAuth do
  @moduledoc """
  Plug that extracts and validates the `x-ichor-operator-id` header.

  Assigns `:operator_id` on the connection or halts with 401 if missing/empty.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn |> get_req_header("x-ichor-operator-id") |> List.first() |> then(&trim_or_nil/1) do
      nil ->
        conn
        |> put_status(401)
        |> json(%{status: "error", reason: "missing_operator_id"})
        |> halt()

      id ->
        assign(conn, :operator_id, id)
    end
  end

  defp trim_or_nil(nil), do: nil

  defp trim_or_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
