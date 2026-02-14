defmodule ObservatoryWeb.DashboardHelpers do
  @moduledoc """
  Helper functions for the Observatory Dashboard LiveView.
  Extracted to keep the main LiveView module focused on mount/handle_* callbacks.
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

  # ═══════════════════════════════════════════════════════
  # Team Derivation from Events
  # ═══════════════════════════════════════════════════════

  def derive_teams(events, disk_teams) do
    event_teams = derive_teams_from_events(events)
    merge_team_sources(event_teams, disk_teams)
  end

  defp derive_teams_from_events(events) do
    # Find TeamCreate events
    team_creates =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "TeamCreate"
      end)
      |> Enum.map(fn e ->
        input = (e.payload || %{})["tool_input"] || %{}
        %{name: input["team_name"], lead_session: e.session_id, created_at: e.inserted_at}
      end)
      |> Enum.reject(fn t -> is_nil(t.name) end)
      |> Enum.uniq_by(& &1.name)

    # Find teammate spawn events (Task tool with team_name)
    spawns =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name == "Task" and
          ((e.payload || %{})["tool_input"] || %{})["team_name"] != nil
      end)

    # Build team structs
    Enum.map(team_creates, fn tc ->
      members =
        spawns
        |> Enum.filter(fn s ->
          ((s.payload || %{})["tool_input"] || %{})["team_name"] == tc.name
        end)
        |> Enum.map(fn s ->
          input = (s.payload || %{})["tool_input"] || %{}
          %{name: input["name"], agent_type: input["subagent_type"], agent_id: nil}
        end)

      %{
        name: tc.name,
        lead_session: tc.lead_session,
        description: nil,
        members: [%{name: "lead", agent_type: "lead", agent_id: tc.lead_session} | members],
        tasks: [],
        source: :events,
        created_at: tc.created_at
      }
    end)
  end

  defp merge_team_sources(event_teams, disk_teams) do
    # Disk teams are authoritative when available
    disk_list =
      disk_teams
      |> Map.values()
      |> Enum.map(fn dt ->
        %{
          name: dt.name,
          lead_session: nil,
          description: dt.description,
          members: dt.members,
          tasks: dt.tasks,
          source: :disk,
          created_at: nil
        }
      end)

    # Merge: disk data wins for teams that exist in both
    disk_names = MapSet.new(disk_list, & &1.name)

    event_only =
      Enum.reject(event_teams, fn t -> MapSet.member?(disk_names, t.name) end)

    disk_list ++ event_only
  end

  def team_member_sids(team) do
    team.members
    |> Enum.map(& &1[:agent_id])
    |> Enum.reject(&is_nil/1)
  end

  def all_team_sids(teams) do
    teams
    |> Enum.flat_map(&team_member_sids/1)
    |> MapSet.new()
  end

  def enrich_team_members(team, events, now) do
    Map.update!(team, :members, fn members ->
      Enum.map(members, fn m ->
        member_events =
          if m[:agent_id] do
            Enum.filter(events, &(&1.session_id == m[:agent_id]))
          else
            []
          end

        latest =
          member_events
          |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
          |> List.first()

        status =
          cond do
            latest == nil -> :unknown
            latest.hook_event_type == :SessionEnd -> :ended
            DateTime.diff(now, latest.inserted_at, :second) > 30 -> :idle
            true -> :active
          end

        Map.merge(m, %{
          event_count: length(member_events),
          latest_event: latest,
          status: status
        })
      end)
    end)
  end

  # ═══════════════════════════════════════════════════════
  # Task + Message Derivation from Events
  # ═══════════════════════════════════════════════════════

  def derive_tasks(events) do
    # Build task state from TaskCreate/TaskUpdate events
    task_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name in ["TaskCreate", "TaskUpdate"]
      end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    Enum.reduce(task_events, %{}, fn e, acc ->
      input = (e.payload || %{})["tool_input"] || %{}

      case e.tool_name do
        "TaskCreate" ->
          id = map_size(acc) + 1 |> to_string()

          task = %{
            id: id,
            subject: input["subject"],
            description: input["description"],
            status: "pending",
            owner: nil,
            active_form: input["activeForm"],
            session_id: e.session_id,
            created_at: e.inserted_at
          }

          Map.put(acc, id, task)

        "TaskUpdate" ->
          task_id = input["taskId"]

          if task_id && Map.has_key?(acc, task_id) do
            task = acc[task_id]

            task =
              task
              |> maybe_put(:status, input["status"])
              |> maybe_put(:owner, input["owner"])
              |> maybe_put(:subject, input["subject"])

            Map.put(acc, task_id, task)
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  def derive_messages(events) do
    events
    |> Enum.filter(fn e ->
      e.hook_event_type == :PreToolUse and e.tool_name == "SendMessage"
    end)
    |> Enum.map(fn e ->
      input = (e.payload || %{})["tool_input"] || %{}

      %{
        id: e.id,
        sender_session: e.session_id,
        sender_app: e.source_app,
        type: input["type"] || "message",
        recipient: input["recipient"],
        content: input["content"] || input["summary"] || "",
        summary: input["summary"],
        timestamp: e.inserted_at
      }
    end)
  end

  # ═══════════════════════════════════════════════════════
  # Event Filtering + Search
  # ═══════════════════════════════════════════════════════

  def filtered_events(assigns) do
    assigns.events
    |> maybe_filter(:source_app, assigns.filter_source_app)
    |> maybe_filter(:session_id, assigns.filter_session_id)
    |> maybe_filter(:hook_event_type, assigns.filter_event_type)
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
    input = (event.payload || %{})["tool_input"] || %{}

    [
      event.source_app,
      event.session_id,
      to_string(event.hook_event_type),
      event.tool_name,
      event.tool_use_id,
      event.summary,
      event.cwd,
      event.permission_mode,
      event.model_name,
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
      input["team_name"],
      (event.payload || %{})["message"],
      (event.payload || %{})["prompt"],
      (event.payload || %{})["error"],
      (event.payload || %{})["agent_type"],
      (event.payload || %{})["notification_type"],
      (event.payload || %{})["reason"],
      (event.payload || %{})["model"]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

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

  defp maybe_filter(events, :hook_event_type, value) do
    atom_val = String.to_existing_atom(value)
    Enum.filter(events, &(&1.hook_event_type == atom_val))
  end

  defp maybe_filter(events, field, value) do
    Enum.filter(events, &(Map.get(&1, field) == value))
  end

  def blank_to_nil(""), do: nil
  def blank_to_nil(val), do: val

  def unique_values(events, field) do
    events |> Enum.map(&Map.get(&1, field)) |> Enum.uniq() |> Enum.sort()
  end

  # ═══════════════════════════════════════════════════════
  # Session + Display Helpers
  # ═══════════════════════════════════════════════════════

  def short_session(session_id) when is_binary(session_id), do: String.slice(session_id, 0..7)
  def short_session(_), do: "?"

  def format_time(dt), do: Calendar.strftime(dt, "%H:%M:%S")

  def relative_time(dt, now) do
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 2 -> "now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3600)}h ago"
    end
  end

  def session_color(session_id) do
    Enum.at(@session_palette, session_color_index(session_id))
  end

  defp session_color_index(session_id) when is_binary(session_id) do
    :erlang.phash2(session_id, length(@session_palette))
  end

  defp session_color_index(_session_id), do: 0

  def event_type_label(type) do
    Map.get(@event_type_labels, type, {"?", "text-zinc-400 bg-zinc-500/15"})
  end

  def format_duration(nil), do: nil
  def format_duration(ms) when ms < 1000, do: "#{ms}ms"

  def format_duration(ms) do
    secs = ms / 1000

    if secs < 60,
      do: "#{Float.round(secs, 1)}s",
      else: "#{div(ms, 60_000)}m#{rem(div(ms, 1000), 60)}s"
  end

  def active_sessions(events) do
    events
    |> Enum.group_by(&{&1.source_app, &1.session_id})
    |> Enum.map(fn {{app, sid}, evts} ->
      sorted = Enum.sort_by(evts, & &1.inserted_at, {:desc, DateTime})
      latest = hd(sorted)
      ended? = Enum.any?(evts, &(&1.hook_event_type == :SessionEnd))

      %{
        source_app: app,
        session_id: sid,
        event_count: length(evts),
        latest_event: latest,
        first_event: List.last(sorted),
        ended?: ended?,
        model: find_model(evts),
        permission_mode: latest.permission_mode,
        cwd: latest.cwd || find_cwd(evts)
      }
    end)
    |> Enum.sort_by(& &1.latest_event.inserted_at, {:desc, DateTime})
  end

  defp find_model(events), do: Enum.find_value(events, fn e -> e.payload["model"] || e.model_name end)
  defp find_cwd(events), do: Enum.find_value(events, fn e -> e.cwd end)

  def session_duration(first_event, now) do
    diff = DateTime.diff(now, first_event.inserted_at, :second)

    cond do
      diff < 60 -> "#{diff}s"
      diff < 3600 -> "#{div(diff, 60)}m"
      true -> "#{div(diff, 3600)}h#{rem(div(diff, 60), 60)}m"
    end
  end

  # ═══════════════════════════════════════════════════════
  # Event Summary
  # ═══════════════════════════════════════════════════════

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

  def format_payload(payload) when is_map(payload), do: Jason.encode!(payload, pretty: true)
  def format_payload(payload), do: inspect(payload)

  def is_team_tool?(tool_name), do: tool_name in @team_tools

  def member_status_color(:active), do: "bg-emerald-500"
  def member_status_color(:idle), do: "bg-amber-500"
  def member_status_color(:ended), do: "bg-zinc-600"
  def member_status_color(_), do: "bg-zinc-700"
end
