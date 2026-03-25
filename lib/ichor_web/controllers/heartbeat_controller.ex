defmodule IchorWeb.HeartbeatController do
  @moduledoc "Records agent heartbeat signals to track liveness."

  use IchorWeb, :controller

  alias Ichor.Events.EventStream, as: EventRuntime

  def create(conn, %{"agent_id" => agent_id, "cluster_id" => cluster_id}) do
    case EventRuntime.record_heartbeat(agent_id, cluster_id) do
      :ok ->
        conn |> put_status(:ok) |> json(%{"status" => "ok"})

      {:error, :event_stream_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{"status" => "error", "reason" => "event stream unavailable"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{"status" => "error", "reason" => "missing required fields: agent_id, cluster_id"})
  end
end
