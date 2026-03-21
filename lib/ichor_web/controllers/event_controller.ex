defmodule IchorWeb.EventController do
  @moduledoc """
  Thin HTTP adapter for hook events.
  All domain logic lives in `Ichor.Signals.EventStream`.
  """
  use IchorWeb, :controller

  alias Ichor.Signals.EventStream

  def create(conn, params) do
    {raw, hook_type, source_app, tmux_session, os_pid} = extract_envelope(params)

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
      tmux_session: tmux_session,
      os_pid: os_pid
    }

    try do
      {:ok, event} = EventStream.ingest_raw(event_attrs)
      conn |> put_status(:created) |> json(%{ok: true, id: event.id})
    rescue
      e ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{ok: false, error: Exception.message(e)})
    end
  end

  defp extract_envelope(%{"raw" => raw} = params) do
    {
      raw,
      params["hook_event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"]),
      coerce_pid(params["os_pid"])
    }
  end

  defp extract_envelope(params) do
    payload = params["payload"] || params

    {
      payload,
      params["hook_event_type"] || params["event_type"] || "Stop",
      params["source_app"] || "unknown",
      nullify_empty(params["tmux_session"]),
      coerce_pid(params["os_pid"])
    }
  end

  defp nullify_empty(""), do: nil
  defp nullify_empty(v), do: v

  defp coerce_pid(v) when is_integer(v) and v > 0, do: v

  defp coerce_pid(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp coerce_pid(_), do: nil
end
