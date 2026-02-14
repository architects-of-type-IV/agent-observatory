defmodule ObservatoryWeb.DashboardFormatHelpers do
  @moduledoc """
  Display and formatting helpers for the Observatory Dashboard.
  Handles colors, time formatting, event summaries, and UI presentation.
  """

  @session_palette [
    {"bg-blue-500", "border-blue-500", "text-blue-400"},
    {"bg-emerald-500", "border-emerald-500", "text-emerald-400"},
    {"bg-violet-500", "border-violet-500", "text-violet-400"},
    {"bg-amber-500", "border-amber-500", "text-amber-400"},
    {"bg-rose-500", "border-rose-500", "text-rose-400"},
    {"bg-cyan-500", "border-cyan-500", "text-cyan-400"},
    {"bg-fuchsia-500", "border-fuchsia-500", "text-fuchsia-400"},
    {"bg-lime-500", "border-lime-500", "text-lime-400"},
    {"bg-orange-500", "border-orange-500", "text-orange-400"},
    {"bg-teal-500", "border-teal-500", "text-teal-400"},
    {"bg-indigo-500", "border-indigo-500", "text-indigo-400"},
    {"bg-pink-500", "border-pink-500", "text-pink-400"}
  ]

  @event_type_labels %{
    SessionStart: {"SESSION", "text-green-400 bg-green-500/15 border border-green-500/30"},
    SessionEnd: {"END", "text-red-400 bg-red-500/15 border border-red-500/30"},
    UserPromptSubmit: {"PROMPT", "text-blue-400 bg-blue-500/15 border border-blue-500/30"},
    PreToolUse: {"TOOL", "text-amber-400 bg-amber-500/15 border border-amber-500/30"},
    PostToolUse: {"DONE", "text-emerald-400 bg-emerald-500/15 border border-emerald-500/30"},
    PostToolUseFailure: {"FAIL", "text-red-400 bg-red-500/15 border border-red-500/30"},
    PermissionRequest: {"PERM", "text-yellow-400 bg-yellow-500/15 border border-yellow-500/30"},
    Notification: {"NOTIF", "text-purple-400 bg-purple-500/15 border border-purple-500/30"},
    SubagentStart: {"SPAWN", "text-cyan-400 bg-cyan-500/15 border border-cyan-500/30"},
    SubagentStop: {"REAP", "text-cyan-600 bg-cyan-600/15 border border-cyan-600/30"},
    Stop: {"STOP", "text-zinc-400 bg-zinc-500/15 border border-zinc-500/30"},
    PreCompact: {"COMPACT", "text-orange-400 bg-orange-500/15 border border-orange-500/30"}
  }

  @team_tools ~w(TeamCreate TeamDelete TaskCreate TaskUpdate TaskList TaskGet SendMessage)

  @doc """
  Get short session ID (first 8 chars).
  """
  def short_session(session_id) when is_binary(session_id), do: String.slice(session_id, 0..7)
  def short_session(_), do: "?"

  @doc """
  Format datetime as HH:MM:SS.
  """
  def format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  @doc """
  Format relative time from now.
  """
  def relative_time(dt, now) do
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 2 -> "now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  @doc """
  Get consistent color classes for a session ID.
  """
  def session_color(session_id) do
    Enum.at(@session_palette, session_color_index(session_id))
  end

  defp session_color_index(session_id) when is_binary(session_id) do
    :erlang.phash2(session_id, length(@session_palette))
  end

  defp session_color_index(_session_id), do: 0

  @doc """
  Get label and badge class for event type.
  """
  def event_type_label(type) do
    Map.get(@event_type_labels, type, {"?", "text-zinc-400 bg-zinc-500/15"})
  end

  @doc """
  Format duration in milliseconds to human-readable string.
  """
  def format_duration(nil), do: nil
  def format_duration(ms) when ms < 1000, do: "#{ms}ms"

  def format_duration(ms) do
    secs = ms / 1000

    if secs < 60,
      do: "#{Float.round(secs, 1)}s",
      else: "#{div(ms, 60_000)}m#{rem(div(ms, 1000), 60)}s"
  end

  @doc """
  Calculate session duration from first event to now.
  """
  def session_duration(first_event, now) do
    diff = DateTime.diff(now, first_event.inserted_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h#{rem(div(diff, 60), 60)}m"
    end
  end

  @doc """
  Format duration in seconds for timeline view.
  """
  def session_duration_sec(sec) when sec < 60, do: "#{sec}s"
  def session_duration_sec(sec) when sec < 3600, do: "#{div(sec, 60)}m"
  def session_duration_sec(sec), do: "#{div(sec, 3600)}h#{rem(div(sec, 60), 60)}m"

  @doc """
  Generate human-readable summary for an event.
  """
  def event_summary(%{hook_event_type: :PreToolUse} = event) do
    tool = event.tool_name || event.payload["tool_name"] || "?"
    input = (event.payload || %{})["tool_input"] || %{}

    case tool do
      "Bash" -> "$ #{truncate(input["command"] || "", 100)}"
      "Read" -> truncate(input["file_path"] || "", 80)
      "Write" -> truncate(input["file_path"] || "", 80)
      "Edit" -> truncate(input["file_path"] || "", 80)
      "Grep" -> "pattern: #{truncate(input["pattern"] || "", 50)}"
      "Glob" -> "pattern: #{truncate(input["pattern"] || "", 50)}"
      "Task" -> truncate(input["description"] || input["prompt"] || "", 80)
      "WebSearch" -> truncate(input["query"] || "", 60)
      "WebFetch" -> truncate(input["url"] || "", 60)
      "SendMessage" -> "to #{input["recipient"] || "?"}: #{truncate(input["content"] || "", 50)}"
      "TaskCreate" -> truncate(input["subject"] || "", 60)
      "TaskUpdate" -> "task #{input["taskId"] || "?"} -> #{input["status"] || "?"}"
      "TeamCreate" -> "team: #{input["team_name"] || "?"}"
      "TeamDelete" -> "cleanup"
      _ -> tool
    end
  end

  def event_summary(%{hook_event_type: :PostToolUse} = event) do
    tool = event.tool_name || event.payload["tool_name"] || "?"
    dur = format_duration(event.duration_ms)
    if dur, do: "#{tool} (#{dur})", else: tool
  end

  def event_summary(%{hook_event_type: :PostToolUseFailure} = event) do
    tool = event.tool_name || event.payload["tool_name"] || "?"
    error = event.payload["error"] || "unknown error"
    "#{tool}: #{truncate(error, 80)}"
  end

  def event_summary(%{hook_event_type: :UserPromptSubmit} = event) do
    msg = event.payload["message"] || event.payload["prompt"] || ""
    truncate(msg, 120)
  end

  def event_summary(%{hook_event_type: :SessionStart} = event) do
    model = event.payload["model"] || "?"
    type = event.payload["agent_type"] || event.payload["source"] || "agent"
    "#{type} (#{model})"
  end

  def event_summary(%{hook_event_type: :SessionEnd} = event) do
    event.payload["reason"] || "completed"
  end

  def event_summary(%{hook_event_type: :SubagentStart} = event) do
    truncate(event.payload["description"] || event.payload["agent_type"] || "subagent", 80)
  end

  def event_summary(%{hook_event_type: :SubagentStop} = event) do
    short_session(event.payload["agent_id"] || "?")
  end

  def event_summary(%{hook_event_type: :PermissionRequest} = event), do: event.payload["tool_name"] || "?"
  def event_summary(%{hook_event_type: :Notification} = event), do: event.payload["notification_type"] || "notification"
  def event_summary(%{hook_event_type: :PreCompact}), do: "context compaction"
  def event_summary(%{hook_event_type: :Stop}), do: "response complete"
  def event_summary(_event), do: ""

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max, do: String.slice(str, 0, max) <> "..."
  defp truncate(str, _max) when is_binary(str), do: str
  defp truncate(_, _), do: ""

  @doc """
  Format payload as pretty JSON.
  """
  def format_payload(payload) when is_map(payload), do: Jason.encode!(payload, pretty: true)
  def format_payload(payload), do: inspect(payload)

  @doc """
  Check if tool is a team coordination tool.
  """
  def is_team_tool?(tool_name), do: tool_name in @team_tools

  @doc """
  Get color class for duration based on threshold.
  Gray <1s, amber 1-5s, red >5s.
  """
  def duration_color(nil), do: "text-zinc-600"
  def duration_color(ms) when ms < 1000, do: "text-zinc-600"
  def duration_color(ms) when ms < 5000, do: "text-amber-400"
  def duration_color(_ms), do: "text-red-400"

  @doc """
  Build export URL with current filter parameters.
  """
  def build_export_url(session_id, search, event_type, format) do
    params =
      []
      |> maybe_add_param("session_id", session_id)
      |> maybe_add_param("search", search)
      |> maybe_add_param("hook_event_type", event_type)
      |> maybe_add_param("format", format)

    query_string = URI.encode_query(params)
    "/export/events?" <> query_string
  end

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, _key, ""), do: params
  defp maybe_add_param(params, key, value), do: [{key, value} | params]
end
