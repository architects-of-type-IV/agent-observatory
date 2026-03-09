defmodule IchorWeb.EventController do
  @moduledoc """
  Thin HTTP adapter for hook events.
  All domain logic lives in EventBuffer, Costs, and Gateway.Router.
  """
  use IchorWeb, :controller

  def create(conn, params) do
    {raw, hook_type, source_app, tmux_session} = extract_envelope(params)

    event_attrs = %{
      source_app: source_app,
      session_id: raw["session_id"] || params["session_id"] || "unknown",
      hook_event_type: hook_type,
      payload: raw,
      summary: raw["summary"] || params["summary"],
      model_name: raw["model"] || raw["model_name"] || params["model_name"],
      tool_name: raw["tool_name"],
      tool_use_id: raw["tool_use_id"],
      cwd: raw["cwd"],
      permission_mode: raw["permission_mode"],
      tmux_session: tmux_session
    }

    {:ok, event} = Ichor.EventBuffer.ingest(event_attrs)

    Ichor.Costs.CostAggregator.record_usage(event, raw)

    Phoenix.PubSub.broadcast(
      Ichor.PubSub,
      "events:stream",
      {:new_event, event}
    )

    Ichor.Gateway.Router.ingest(event)

    conn
    |> put_status(:created)
    |> json(%{ok: true, id: event.id})
  end

  # ── Envelope Extraction ──────────────────────────────────────────

  defp extract_envelope(%{"raw" => raw} = params) do
    {
      raw,
      params["hook_event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"])
    }
  end

  defp extract_envelope(params) do
    payload = params["payload"] || params

    {
      payload,
      params["hook_event_type"] || params["event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"])
    }
  end

  defp nullify_empty(""), do: nil
  defp nullify_empty(v), do: v
end
