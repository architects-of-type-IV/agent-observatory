defmodule IchorWeb.ExportController do
  @moduledoc "Exports event data as JSON or CSV for download."

  use IchorWeb, :controller
  alias Ichor.Signals.EventStream

  def index(conn, params) do
    format = params["format"] || "json"

    events =
      EventStream.list_events()
      |> apply_filters(params)
      |> Enum.sort_by(& &1.inserted_at, DateTime)

    case format do
      "csv" -> export_csv(conn, events)
      "json" -> export_json(conn, events)
      _ -> export_json(conn, events)
    end
  end

  defp apply_filters(events, params) do
    events
    |> filter_by_session(params["session_id"])
    |> filter_by_tool(params["tool"])
    |> filter_by_event_type(params["hook_event_type"])
    |> filter_by_search(params["search"])
  end

  defp filter_by_session(events, nil), do: events
  defp filter_by_session(events, ""), do: events

  defp filter_by_session(events, session_id) do
    Enum.filter(events, &(&1.session_id == session_id))
  end

  defp filter_by_tool(events, nil), do: events
  defp filter_by_tool(events, ""), do: events

  defp filter_by_tool(events, tool) do
    Enum.filter(events, &(&1.tool_name == tool))
  end

  defp filter_by_event_type(events, nil), do: events
  defp filter_by_event_type(events, ""), do: events

  @hook_event_type_map %{
    "SessionStart" => :SessionStart,
    "SessionEnd" => :SessionEnd,
    "UserPromptSubmit" => :UserPromptSubmit,
    "PreToolUse" => :PreToolUse,
    "PostToolUse" => :PostToolUse,
    "PostToolUseFailure" => :PostToolUseFailure,
    "PermissionRequest" => :PermissionRequest,
    "Notification" => :Notification,
    "SubagentStart" => :SubagentStart,
    "SubagentStop" => :SubagentStop,
    "Stop" => :Stop,
    "PreCompact" => :PreCompact,
    "TaskCompleted" => :TaskCompleted
  }

  defp filter_by_event_type(events, event_type) do
    case Map.fetch(@hook_event_type_map, event_type) do
      {:ok, atom_val} -> Enum.filter(events, &(&1.hook_event_type == atom_val))
      :error -> events
    end
  end

  defp filter_by_search(events, nil), do: events
  defp filter_by_search(events, ""), do: events

  defp filter_by_search(events, search_term) do
    search_lower = String.downcase(search_term)

    Enum.filter(events, fn e ->
      String.contains?(String.downcase(e.tool_name || ""), search_lower) or
        String.contains?(String.downcase(e.session_id || ""), search_lower) or
        String.contains?(String.downcase(e.source_app || ""), search_lower) or
        String.contains?(String.downcase(e.summary || ""), search_lower)
    end)
  end

  defp export_json(conn, events) do
    data = Enum.map(events, &serialize_event/1)

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("content-disposition", "attachment; filename=\"events.json\"")
    |> json(data)
  end

  defp export_csv(conn, events) do
    headers = [
      "id",
      "inserted_at",
      "hook_event_type",
      "tool_name",
      "source_app",
      "session_id",
      "summary",
      "duration_ms",
      "cwd",
      "permission_mode"
    ]

    rows =
      Enum.map(events, fn e ->
        [
          csv_escape(e.id),
          csv_escape(e.inserted_at),
          csv_escape(e.hook_event_type),
          csv_escape(e.tool_name),
          csv_escape(e.source_app),
          csv_escape(e.session_id),
          csv_escape(e.summary),
          csv_escape(e.duration_ms),
          csv_escape(e.cwd),
          csv_escape(e.permission_mode)
        ]
      end)

    csv_content =
      Enum.map_join([headers | rows], "\n", &Enum.join(&1, ","))

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"events.csv\"")
    |> send_resp(200, csv_content)
  end

  defp csv_escape(nil), do: "\"\""

  defp csv_escape(v) do
    s = to_string(v)
    "\"" <> String.replace(s, "\"", "\"\"") <> "\""
  end

  defp serialize_event(event) do
    %{
      id: event.id,
      inserted_at: event.inserted_at,
      hook_event_type: event.hook_event_type,
      tool_name: event.tool_name,
      tool_use_id: event.tool_use_id,
      source_app: event.source_app,
      session_id: event.session_id,
      summary: event.summary,
      duration_ms: event.duration_ms,
      cwd: event.cwd,
      permission_mode: event.permission_mode,
      model_name: event.model_name,
      payload: event.payload
    }
  end
end
