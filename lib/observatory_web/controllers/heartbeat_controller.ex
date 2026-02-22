defmodule ObservatoryWeb.HeartbeatController do
  use ObservatoryWeb, :controller

  require Logger

  alias Observatory.Gateway.HeartbeatManager

  def create(conn, %{"agent_id" => agent_id, "cluster_id" => cluster_id}) do
    HeartbeatManager.record_heartbeat(agent_id, cluster_id)

    conn
    |> put_status(:ok)
    |> json(%{"status" => "ok"})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"status" => "error", "reason" => "missing required fields: agent_id, cluster_id"})
  end
end
