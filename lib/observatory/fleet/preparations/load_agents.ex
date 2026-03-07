defmodule Observatory.Fleet.Preparations.LoadAgents do
  @moduledoc """
  Loads agent data from EventBuffer events and tmux sessions.
  Shared preparation for all Fleet.Agent read actions.
  """

  use Ash.Resource.Preparation

  @idle_threshold_seconds 120

  @impl true
  def prepare(query, _opts, _context) do
    events = Observatory.EventBuffer.list_events()
    now = DateTime.utc_now()
    teams = Observatory.Fleet.Team.alive!()
    tmux_sessions = list_tmux_sessions()

    agents =
      events
      |> build_from_events(now)
      |> enrich_with_teams(teams)
      |> append_disk_only_members(teams, now)
      |> append_tmux_only(tmux_sessions)
      |> sort_agents()

    Ash.DataLayer.Simple.set_data(query, agents)
  end

  defp build_from_events(events, now) do
    events
    |> Enum.group_by(& &1.session_id)
    |> Enum.map(fn {session_id, evts} -> build_agent(session_id, evts, now) end)
  end

  defp build_agent(session_id, events, now) do
    sorted = Enum.sort_by(events, & &1.inserted_at, {:desc, DateTime})
    latest = hd(sorted)
    ended? = Enum.any?(events, &(&1.hook_event_type == :SessionEnd))
    cwd = latest.cwd || Enum.find_value(events, & &1.cwd)

    model =
      Enum.find_value(events, fn e ->
        if e.hook_event_type == :SessionStart,
          do: (e.payload || %{})["model"] || e.model_name
      end) || Enum.find_value(events, & &1.model_name)

    status =
      cond do
        ended? -> :ended
        DateTime.diff(now, latest.inserted_at, :second) > @idle_threshold_seconds -> :idle
        true -> :active
      end

    struct!(Observatory.Fleet.Agent, %{
      agent_id: session_id,
      name: if(cwd, do: Path.basename(cwd), else: String.slice(session_id, 0, 8)),
      role: nil,
      model: model,
      status: status,
      health: :unknown,
      current_tool: find_current_tool(events, now),
      event_count: length(events),
      tool_count: Enum.count(events, &(&1.hook_event_type == :PreToolUse)),
      cwd: cwd,
      source_app: latest.source_app,
      project: if(cwd, do: Path.basename(cwd), else: nil),
      health_issues: [],
      team_name: nil,
      tmux_session: Enum.find_value(events, & &1.tmux_session),
      recent_activity: build_recent_activity(sorted, now)
    })
  end

  defp enrich_with_teams(agents, teams) do
    team_index =
      teams
      |> Enum.flat_map(fn team ->
        Enum.map(team.members, fn m ->
          role = m[:name] || m[:agent_type]
          {m[:agent_id] || m[:session_id], %{team_name: team.name, role: role}}
        end)
      end)
      |> Map.new()

    Enum.map(agents, fn agent ->
      case Map.get(team_index, agent.agent_id) do
        nil -> agent
        data -> %{agent | team_name: data.team_name, role: data.role}
      end
    end)
  end

  defp append_disk_only_members(agents, teams, _now) do
    event_sids = MapSet.new(agents, & &1.agent_id)

    disk_agents =
      teams
      |> Enum.flat_map(fn team ->
        team.members
        |> Enum.filter(fn m -> m[:agent_id] && not MapSet.member?(event_sids, m[:agent_id]) end)
        |> Enum.map(fn m ->
          struct!(Observatory.Fleet.Agent, %{
            agent_id: m[:agent_id],
            name: m[:name] || m[:agent_type] || String.slice(m[:agent_id] || "", 0, 8),
            role: m[:name] || m[:agent_type],
            model: m[:model],
            status: m[:status] || :idle,
            health: :unknown,
            current_tool: nil,
            event_count: m[:event_count] || 0,
            tool_count: 0,
            cwd: m[:cwd],
            source_app: nil,
            project: if(m[:cwd], do: Path.basename(m[:cwd]), else: nil),
            health_issues: [],
            team_name: team.name,
            tmux_session: nil,
            recent_activity: []
          })
        end)
      end)

    agents ++ disk_agents
  end

  defp append_tmux_only(agents, tmux_sessions) do
    known_tmux =
      agents
      |> Enum.map(& &1.tmux_session)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    tmux_agents =
      tmux_sessions
      |> Enum.reject(fn name -> MapSet.member?(known_tmux, name) end)
      |> Enum.map(fn name ->
        struct!(Observatory.Fleet.Agent, %{
          agent_id: "tmux:#{name}",
          name: name,
          role: nil,
          model: nil,
          status: :active,
          health: :unknown,
          current_tool: nil,
          event_count: 0,
          tool_count: 0,
          cwd: nil,
          source_app: nil,
          project: nil,
          health_issues: [],
          team_name: nil,
          tmux_session: name,
          recent_activity: []
        })
      end)

    agents ++ tmux_agents
  end

  defp sort_agents(agents) do
    Enum.sort_by(agents, fn a -> {status_sort(a.status), a.name} end)
  end

  defp status_sort(:active), do: 0
  defp status_sort(:idle), do: 1
  defp status_sort(_), do: 2

  defp find_current_tool(events, now) do
    post_ids =
      events
      |> Enum.filter(&(&1.hook_event_type in [:PostToolUse, :PostToolUseFailure]))
      |> MapSet.new(& &1.tool_use_id)

    events
    |> Enum.filter(&(&1.hook_event_type == :PreToolUse))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find(fn e -> e.tool_use_id && not MapSet.member?(post_ids, e.tool_use_id) end)
    |> case do
      nil -> nil
      pre -> %{tool_name: pre.tool_name, elapsed: div(DateTime.diff(now, pre.inserted_at, :millisecond), 1000)}
    end
  end

  defp build_recent_activity(sorted_events, now) do
    sorted_events
    |> Enum.take(20)
    |> Enum.flat_map(fn e -> event_to_activity(e, now) end)
    |> Enum.take(5)
  end

  defp event_to_activity(e, now) do
    age = DateTime.diff(now, e.inserted_at, :second)
    age_str = format_age(age)
    payload = e.payload || %{}

    case e.hook_event_type do
      :PreToolUse ->
        tool = e.tool_name || "?"
        detail = extract_tool_detail(tool, payload)
        [%{type: :tool, tool: tool, detail: detail, age: age_str}]

      :PostToolUseFailure ->
        tool = e.tool_name || "?"
        [%{type: :error, tool: tool, detail: "failed", age: age_str}]

      :Notification ->
        text = payload["message"] || payload["content"] || e.summary || ""
        if text != "", do: [%{type: :notify, detail: String.slice(text, 0, 120), age: age_str}], else: []

      :TaskCompleted ->
        task_id = payload["task_id"] || "?"
        [%{type: :task_done, detail: "Task #{task_id} completed", age: age_str}]

      _ ->
        []
    end
  end

  defp extract_tool_detail("SendMessage", payload) do
    to = payload["recipient"] || payload["target_agent_id"] || payload["to"] ||
         get_in(payload, ["input", "recipient"]) || "?"
    content = payload["content"] || payload["summary"] ||
              get_in(payload, ["input", "content"]) || ""
    "-> #{to}: #{String.slice(content, 0, 80)}"
  end

  defp extract_tool_detail("Read", payload), do: basename_from(payload, "file_path")
  defp extract_tool_detail("Edit", payload), do: basename_from(payload, "file_path")
  defp extract_tool_detail("Write", payload), do: basename_from(payload, "file_path")

  defp extract_tool_detail("Bash", payload) do
    cmd = payload["command"] || payload["description"] || get_in(payload, ["input", "command"]) || ""
    String.slice(cmd, 0, 60)
  end

  defp extract_tool_detail("Grep", payload), do: slice_field(payload, "pattern", 40)
  defp extract_tool_detail("Glob", payload), do: slice_field(payload, "pattern", 40)

  defp extract_tool_detail("Task", payload) do
    desc = payload["description"] || get_in(payload, ["input", "description"]) || ""
    String.slice(desc, 0, 60)
  end

  defp extract_tool_detail(_tool, _payload), do: ""

  defp basename_from(payload, key) do
    path = payload[key] || get_in(payload, ["input", key]) || ""
    if path != "", do: Path.basename(path), else: ""
  end

  defp slice_field(payload, key, len) do
    val = payload[key] || get_in(payload, ["input", key]) || ""
    String.slice(val, 0, len)
  end

  defp format_age(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_age(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"
  defp format_age(seconds), do: "#{div(seconds, 3600)}h"

  defp list_tmux_sessions do
    Observatory.Gateway.Channels.Tmux.list_sessions()
  rescue
    _ -> []
  end
end
