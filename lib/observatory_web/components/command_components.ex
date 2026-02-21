defmodule ObservatoryWeb.Components.CommandComponents do
  @moduledoc """
  Command Center view -- the operational cockpit for swarm monitoring.
  Shows agent grid, pipeline health, alerts, and selected detail panel.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.ObservatoryComponents

  embed_templates "command_components/*"

  # ═══════════════════════════════════════════════════════
  # Data collection helpers
  # ═══════════════════════════════════════════════════════

  defp collect_agents(teams, _events, _now) do
    teams
    |> Enum.flat_map(fn team ->
      Enum.map(team.members, fn m ->
        Map.merge(m, %{team_name: team.name})
      end)
    end)
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
