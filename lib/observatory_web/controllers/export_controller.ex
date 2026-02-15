defmodule ObservatoryWeb.ExportController do
  use ObservatoryWeb, :controller
  alias Observatory.Events.Event

  def index(conn, params) do
    format = params["format"] || "json"

    # Load events using Ash
    case Ash.read(Event, action: :read) do
      {:ok, events} ->
        events =
          events
          |> apply_filters(params)
          |> Enum.sort_by(& &1.inserted_at, DateTime)

        case format do
          "csv" -> export_csv(conn, events)
          "json" -> export_json(conn, events)
          _ -> export_json(conn, events)
        end

      {:error, _} ->
        send_resp(conn, 500, "Failed to load events")
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

  defp filter_by_event_type(events, event_type) do
    atom_val = String.to_existing_atom(event_type)
    Enum.filter(events, &(&1.hook_event_type == atom_val))
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
