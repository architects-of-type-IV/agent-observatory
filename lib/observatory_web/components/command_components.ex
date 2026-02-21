defmodule ObservatoryWeb.Components.CommandComponents do
  @moduledoc """
  Command Center view -- the operational cockpit for swarm monitoring.
  Shows agent grid, pipeline health, alerts, and selected detail panel.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.ObservatoryComponents

  embed_templates "command_components/*"

  @idle_threshold_seconds 120

  # ═══════════════════════════════════════════════════════
  # Data collection: derive agents from events + teams
  # ═══════════════════════════════════════════════════════

  defp collect_agents(teams, events, now) do
    # Build agent map from events (every session = a node)
    event_agents =
      events
      |> Enum.group_by(& &1.session_id)
      |> Enum.map(fn {sid, evts} ->
        build_agent_from_events(sid, evts, now)
      end)

    # Enrich with team data
    team_index = build_team_index(teams)

    event_agents
    |> Enum.map(fn agent ->
      case Map.get(team_index, agent.agent_id) do
        nil -> agent
        team_data -> Map.merge(agent, team_data)
      end
    end)
    |> Enum.sort_by(fn a -> {status_sort(a.status), a.name} end)
  end

  defp build_agent_from_events(session_id, events, now) do
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

    %{
      agent_id: session_id,
      name: if(cwd, do: Path.basename(cwd), else: String.slice(session_id, 0, 8)),
      model: model,
      status: status,
      health: :unknown,
      current_tool: find_current_tool(events, now),
      event_count: length(events),
      tool_count: Enum.count(events, &(&1.hook_event_type == :PreToolUse)),
      cwd: cwd,
      source_app: latest.source_app,
      project: if(cwd, do: Path.basename(cwd), else: nil),
      health_issues: []
    }
  end

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
      pre -> {pre.tool_name, div(DateTime.diff(now, pre.inserted_at, :millisecond), 1000)}
    end
  end

  defp build_team_index(teams) do
    teams
    |> Enum.flat_map(fn team ->
      Enum.map(team.members, fn m ->
        {m[:agent_id] || m[:session_id], Map.merge(m, %{team_name: team.name})}
      end)
    end)
    |> Map.new()
  end

  defp status_sort(:active), do: 0
  defp status_sort(:idle), do: 1
  defp status_sort(_), do: 2

  defp fleet_stats(agents) do
    %{
      total: length(agents),
      active: Enum.count(agents, &(&1.status == :active)),
      idle: Enum.count(agents, &(&1.status == :idle)),
      ended: Enum.count(agents, &(&1.status == :ended)),
      by_project: agents |> Enum.frequencies_by(& &1.project) |> Enum.sort_by(&elem(&1, 1), :desc)
    }
  end

  defp build_alerts(issues, stale_tasks) do
    issue_alerts =
      Enum.map(issues, fn issue ->
        %{
          severity: String.downcase(issue.severity),
          message: issue.description,
          action: if(issue.type in ["dead_agent", "stale_task"], do: "heal_task"),
          action_label: "Heal",
          target_id: issue.task_id
        }
      end)

    stale_alerts =
      Enum.map(stale_tasks, fn t ->
        %{
          severity: "medium",
          message: "Task ##{t.id} (#{t.owner}) stale -- #{t.subject}",
          action: "heal_task",
          action_label: "Reset",
          target_id: t.id
        }
      end)

    (issue_alerts ++ stale_alerts)
    |> Enum.uniq_by(& &1.target_id)
    |> Enum.take(20)
  end

  defp progress_pct(%{total: 0}), do: 0
  defp progress_pct(%{total: t, completed: c}), do: round(c / t * 100)

  defp status_dot_color(:active), do: "bg-emerald-400"
  defp status_dot_color(:idle), do: "bg-zinc-500"
  defp status_dot_color(:ended), do: "bg-zinc-700"
  defp status_dot_color(_), do: "bg-zinc-600"

  defp status_text_color(:active), do: "text-emerald-400"
  defp status_text_color(:idle), do: "text-zinc-400"
  defp status_text_color(:ended), do: "text-zinc-600"
  defp status_text_color(_), do: "text-zinc-500"

  defp severity_color("high"), do: "bg-red-400"
  defp severity_color("medium"), do: "bg-amber-400"
  defp severity_color("low"), do: "bg-blue-400"
  defp severity_color(_), do: "bg-zinc-500"

  defp severity_text_color("high"), do: "text-red-400"
  defp severity_text_color("medium"), do: "text-amber-400"
  defp severity_text_color("low"), do: "text-blue-400"
  defp severity_text_color(_), do: "text-zinc-400"

  defp task_status_color("completed"), do: "text-emerald-400"
  defp task_status_color("in_progress"), do: "text-blue-400"
  defp task_status_color("failed"), do: "text-red-400"
  defp task_status_color("pending"), do: "text-zinc-400"
  defp task_status_color(_), do: "text-zinc-500"

  defp short_model(nil), do: ""

  defp short_model(m) when is_binary(m) do
    cond do
      String.contains?(m, "opus") -> "opus"
      String.contains?(m, "sonnet") -> "sonnet"
      String.contains?(m, "haiku") -> "haiku"
      true -> String.slice(m, 0, 8)
    end
  end

  defp short_id(nil), do: "?"
  defp short_id(id) when byte_size(id) > 8, do: String.slice(id, 0, 8) <> "..."
  defp short_id(id), do: id

  defp format_health_issue(:stuck), do: "stuck"
  defp format_health_issue(:looping), do: "looping"
  defp format_health_issue(:high_failure_rate), do: "high fail"
  defp format_health_issue(other), do: to_string(other)
end
