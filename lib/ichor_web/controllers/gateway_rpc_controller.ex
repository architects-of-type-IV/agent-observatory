defmodule IchorWeb.GatewayRpcController do
  @moduledoc """
  Single RPC endpoint for all Gateway message operations.

  POST /gateway/rpc
  Body: {"channel": "agent:worker-7", "payload": {"content": "fix the test", "from": "dashboard"}}
  """

  use IchorWeb, :controller
  require Logger

  alias Ichor.Messages.Bus

  def create(conn, %{"channel" => channel, "payload" => payload})
      when is_binary(channel) and is_map(payload) do
    content = payload["content"] || ""
    from = payload["from"] || "rpc"

    case Bus.send(%{from: from, to: channel, content: content}) do
      {:ok, %{delivered: delivered}} ->
        conn
        |> put_status(:ok)
        |> json(%{ok: true, delivered: delivered})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "broadcast_failed", reason: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing required fields: channel (string), payload (object)"})
  end
end
