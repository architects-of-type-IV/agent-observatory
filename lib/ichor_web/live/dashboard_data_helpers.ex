defmodule IchorWeb.DashboardDataHelpers do
  @moduledoc """
  Data filtering helpers for the Ichor Dashboard.
  Handles event filtering and search.
  """

  @doc """
  Filter events based on assigns (source, session, type, search).
  """
  def filtered_events(assigns) do
    assigns.events
    |> maybe_filter(:source_app, assigns.filter_source_app)
    |> maybe_filter(:session_id, assigns.filter_session_id)
    |> maybe_filter(:hook_event_type, assigns.filter_event_type)
    |> maybe_filter_slow(assigns[:filter_slow])
    |> search_events(assigns.search_feed)
  end

  defp search_events(events, q) when q in [nil, ""], do: events

  defp search_events(events, q) do
    terms = q |> String.downcase() |> String.split(~r/\s+/, trim: true)
    Enum.filter(events, &event_matches?(&1, terms))
  end

  defp event_matches?(event, terms) do
    searchable = event_searchable_text(event)
    Enum.all?(terms, &String.contains?(searchable, &1))
  end

  defp event_searchable_text(event) do
    payload = event.payload || %{}
    input = payload["tool_input"] || %{}

    (event_fields(event) ++
       input_fields(input) ++
       payload_fields(payload))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  defp event_fields(event) do
    [
      event.source_app,
      event.session_id,
      to_string(event.hook_event_type),
      event.tool_name,
      event.tool_use_id,
      event.summary,
      event.cwd,
      event.permission_mode,
      event.model_name
    ]
  end

  defp input_fields(input) do
    [
      input["command"],
      input["file_path"],
      input["pattern"],
      input["query"],
      input["url"],
      input["description"],
      input["prompt"],
      input["subject"],
      input["content"],
      input["recipient"],
      input["team_name"]
    ]
  end

  defp payload_fields(payload) do
    [
      payload["message"],
      payload["prompt"],
      payload["error"],
      payload["agent_type"],
      payload["notification_type"],
      payload["reason"],
      payload["model"]
    ]
  end

  @doc """
  Filter sessions by search query.
  """
  def filtered_sessions(sessions, q) when q in [nil, ""], do: sessions

  def filtered_sessions(sessions, q) do
    terms = q |> String.downcase() |> String.split(~r/\s+/, trim: true)

    Enum.filter(sessions, fn s ->
      searchable =
        [s.source_app, s.session_id, s.model, s.cwd, s.permission_mode]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> String.downcase()

      Enum.all?(terms, &String.contains?(searchable, &1))
    end)
  end

  defp maybe_filter(events, _field, nil), do: events

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

  defp maybe_filter(events, :hook_event_type, value) do
    case Map.fetch(@hook_event_type_map, value) do
      {:ok, atom_val} -> Enum.filter(events, &(&1.hook_event_type == atom_val))
      :error -> events
    end
  end

  defp maybe_filter(events, field, value) do
    Enum.filter(events, &(Map.get(&1, field) == value))
  end

  defp maybe_filter_slow(events, true) do
    Enum.filter(events, fn e ->
      e.duration_ms && e.duration_ms > 5000
    end)
  end

  defp maybe_filter_slow(events, _), do: events

  @doc """
  Convert blank string to nil for filter cleanup.
  """
  def blank_to_nil(""), do: nil
  def blank_to_nil(val), do: val

  @doc """
  Extract unique values for a field across events.
  """
  def unique_values(events, field) do
    events |> Enum.map(&Map.get(&1, field)) |> Enum.uniq() |> Enum.sort()
  end
end
