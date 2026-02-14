defmodule ObservatoryWeb.ExportController do
  use ObservatoryWeb, :controller
  alias Observatory.Repo
  alias Observatory.Events.HookEvent
  import Ecto.Query

  def index(conn, params) do
    format = params["format"] || "json"

    # Build query with filters
    query =
      HookEvent
      |> maybe_filter_session(params["session_id"])
      |> maybe_filter_tool(params["tool"])
      |> maybe_filter_search(params["search"])
      |> maybe_filter_event_type(params["hook_event_type"])
      |> order_by([e], asc: e.inserted_at)

    events = Repo.all(query)

    case format do
      "csv" -> export_csv(conn, events)
      "json" -> export_json(conn, events)
      _ -> export_json(conn, events)
    end
  end

  defp maybe_filter_session(query, nil), do: query
  defp maybe_filter_session(query, ""), do: query
  defp maybe_filter_session(query, session_id) do
    where(query, [e], e.session_id == ^session_id)
  end

  defp maybe_filter_tool(query, nil), do: query
  defp maybe_filter_tool(query, ""), do: query
  defp maybe_filter_tool(query, tool) do
    where(query, [e], e.tool_name == ^tool)
  end

  defp maybe_filter_event_type(query, nil), do: query
  defp maybe_filter_event_type(query, ""), do: query
  defp maybe_filter_event_type(query, event_type) do
    atom_val = String.to_existing_atom(event_type)
    where(query, [e], e.hook_event_type == ^atom_val)
  end

  defp maybe_filter_search(query, nil), do: query
  defp maybe_filter_search(query, ""), do: query
  defp maybe_filter_search(query, search_term) do
    # Simple search on key fields
    pattern = "%#{search_term}%"
    where(query, [e],
      ilike(e.tool_name, ^pattern) or
      ilike(e.session_id, ^pattern) or
      ilike(e.source_app, ^pattern) or
      ilike(e.summary, ^pattern)
    )
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
      "id", "inserted_at", "hook_event_type", "tool_name", "source_app",
      "session_id", "summary", "duration_ms", "cwd", "permission_mode"
    ]

    rows = Enum.map(events, fn e ->
      [
        to_string(e.id),
        to_string(e.inserted_at),
        to_string(e.hook_event_type),
        e.tool_name || "",
        e.source_app || "",
        e.session_id || "",
        e.summary || "",
        to_string(e.duration_ms || ""),
        e.cwd || "",
        e.permission_mode || ""
      ]
    end)

    csv_content =
      [headers | rows]
      |> Enum.map(&Enum.join(&1, ","))
      |> Enum.join("\n")

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=\"events.csv\"")
    |> send_resp(200, csv_content)
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
