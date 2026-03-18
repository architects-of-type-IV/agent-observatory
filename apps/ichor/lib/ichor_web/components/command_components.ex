defmodule IchorWeb.Components.CommandComponents do
  @moduledoc """
  Command Center view -- the operational cockpit for swarm monitoring.
  Shows agent grid, pipeline health, alerts, and selected detail panel.
  """

  use Phoenix.Component
  import IchorWeb.DashboardFormatHelpers
  import IchorWeb.IchorComponents
  import IchorWeb.Components.FeedComponents, only: [feed_view: 1]

  import IchorWeb.Presentation,
    only: [
      member_status_dot_class: 1,
      member_status_text_class: 1,
      severity_bg_class: 1,
      severity_text_class: 1,
      task_status_text_class: 1,
      short_id: 1
    ]

  alias IchorWeb.Components.FleetHelpers, as: FH

  embed_templates "command_components/*"

  def fleet_status_bar(assigns) do
    assigns = assign_fleet_stats(assigns)

    ~H"""
    <div class="flex items-center gap-2 text-[10px]">
      <div
        class="ichor-tip ichor-tip-bottom flex items-center gap-1"
        data-tip={"#{@stats.total} agents: #{@stats.active} active, #{@stats.idle} idle, #{@stats.ended} ended"}
      >
        <span class="font-bold text-high">{@stats.total}</span>
        <div class="flex items-center gap-1 font-mono">
          <span :if={@stats.active > 0} class="text-success">{@stats.active}a</span>
          <span :if={@stats.idle > 0} class="text-default">{@stats.idle}i</span>
          <span :if={@stats.ended > 0} class="text-muted">{@stats.ended}e</span>
        </div>
      </div>
      <span class="w-px h-3 bg-raised" />
      <div
        class={[
          "ichor-tip ichor-tip-bottom flex items-center gap-1",
          if(@error_count > 0, do: "text-error", else: "text-muted")
        ]}
        data-tip={"#{@error_count} tool errors"}
      >
        <span class={[
          "w-1.5 h-1.5 rounded-full",
          if(@error_count > 0, do: "bg-error", else: "bg-highlight")
        ]} />
        <span class="font-mono">{@error_count}</span><span>err</span>
      </div>
      <div
        class="ichor-tip ichor-tip-bottom flex items-center gap-1 text-low"
        data-tip={"#{@msg_count} messages in mailbox"}
      >
        <span class="font-mono">{@msg_count}</span><span>msg</span>
      </div>
      <div
        class="ichor-tip ichor-tip-bottom flex items-center gap-1 text-low"
        data-tip={"#{@tool_count} total tool calls"}
      >
        <span class="font-mono">{@tool_count}</span><span>tools</span>
      </div>
      <div
        class="ichor-tip ichor-tip-bottom flex items-center gap-1 text-low"
        data-tip={"#{@visible_count} visible / #{@event_count} total events"}
      >
        <span class="font-mono">{@visible_count}/{@event_count}</span><span>events</span>
      </div>
      <span class="w-px h-3 bg-raised" />
      <div
        :if={@task_count > 0}
        class="ichor-tip ichor-tip-bottom flex items-center gap-1"
        data-tip={"Tasks: #{@task_done} completed / #{@task_count} total (#{if @task_count > 0, do: round(@task_done / @task_count * 100), else: 0}%)"}
      >
        <% pct = if @task_count > 0, do: round(@task_done / @task_count * 100), else: 0 %>
        <div class="w-12 h-1 bg-raised rounded-full overflow-hidden">
          <div class="h-full bg-success rounded-full" style={"width: #{pct}%"} />
        </div>
        <span class="font-mono text-low">{@task_done}/{@task_count}</span>
      </div>
      <div
        :if={@pipeline.total > 0 && @pipeline.total != @task_count}
        class="ichor-tip ichor-tip-bottom flex items-center gap-1"
        data-tip={"Pipeline: #{@pipeline.completed} completed / #{@pipeline.total} total"}
      >
        <% ppct = progress_pct(@pipeline) %>
        <div class="w-10 h-1 bg-raised rounded-full overflow-hidden">
          <div class="h-full bg-cyan rounded-full" style={"width: #{ppct}%"} />
        </div>
        <span class="font-mono text-low">{@pipeline.completed}/{@pipeline.total}</span>
      </div>
      <div
        class={[
          "ichor-tip ichor-tip-bottom flex items-center gap-1 ichor-badge",
          if(@health.healthy && @error_count == 0,
            do: "ichor-badge-green",
            else: "ichor-badge-red"
          )
        ]}
        data-tip={
          if(@health.healthy && @error_count == 0,
            do: "Fleet healthy",
            else: "#{@error_count} errors, #{length(@health.issues)} health issues"
          )
        }
      >
        <span class={[
          "w-1.5 h-1.5 rounded-full",
          if(@health.healthy && @error_count == 0, do: "bg-success", else: "bg-error animate-pulse")
        ]} />
        {cond do
          @error_count > 0 && !@health.healthy -> "#{@error_count + length(@health.issues)}!"
          @error_count > 0 -> "#{@error_count}!"
          !@health.healthy -> "#{length(@health.issues)}!"
          true -> "OK"
        end}
      </div>
      <div
        :if={@proto_traces + @proto_mailbox + @proto_cmdq > 0}
        class="ichor-tip ichor-tip-bottom flex items-center gap-1 font-mono text-muted"
        data-tip={"Protocol: #{@proto_traces} traces, #{@proto_mailbox} mailbox pending, #{@proto_cmdq} command queue pending"}
      >
        <span :if={@proto_traces > 0}>T:{@proto_traces}</span>
        <span :if={@proto_mailbox > 0}>M:{@proto_mailbox}</span>
        <span :if={@proto_cmdq > 0}>Q:{@proto_cmdq}</span>
      </div>
    </div>
    """
  end

  # Agent data collection moved to DashboardState.build_agent_index/3
  # The unified agent_index is built in recompute() and passed as @agent_index

  defp assign_fleet_stats(assigns) do
    agent_index = assigns[:agent_index] || %{}
    agents = agent_index |> Map.values() |> Enum.uniq_by(&agent_key/1)
    active_tasks = assigns[:active_tasks] || []
    protocol_stats = assigns[:protocol_stats] || %{}
    dag_state = assigns[:dag_state] || assigns[:swarm_state] || %{}

    assigns
    |> assign(:stats, fleet_stats(agents))
    |> assign(:pipeline, Map.get(dag_state, :pipeline, %{}))
    |> assign(:health, Map.get(dag_state, :health, %{}))
    |> assign(:error_count, length(assigns[:errors] || []))
    |> assign(:msg_count, length(assigns[:messages] || []))
    |> assign(:task_count, length(active_tasks))
    |> assign(:task_done, Enum.count(active_tasks, &task_done?/1))
    |> assign_protocol_stats(agents, protocol_stats)
  end

  defp assign_protocol_stats(assigns, agents, protocol_stats) do
    assigns
    |> assign(:tool_count, sum_tool_count(agents))
    |> assign(:proto_traces, protocol_stats[:traces] || 0)
    |> assign(:proto_mailbox, get_in(protocol_stats, [:mailbox, :total_unread]) || 0)
    |> assign(:proto_cmdq, get_in(protocol_stats, [:command_queue, :total_pending]) || 0)
    |> assign(:visible_count, length(assigns[:visible_events] || []))
    |> assign(:event_count, length(assigns[:events] || []))
  end

  defp agent_key(a), do: a[:session_id] || a[:agent_id]
  defp task_done?(t), do: t[:status] == "completed"

  defp sum_tool_count(agents) do
    agents
    |> Enum.map(fn a -> if is_integer(a.tool_count), do: a.tool_count, else: 0 end)
    |> Enum.sum()
  end

  defp fleet_stats(agents) do
    %{
      total: length(agents),
      active: Enum.count(agents, &(&1.status == :active)),
      idle: Enum.count(agents, &(&1.status == :idle)),
      ended: Enum.count(agents, &(&1.status == :ended))
    }
  end

  # ═══════════════════════════════════════════════════════
  # Cluster hierarchy: project -> swarm -> agent
  # ═══════════════════════════════════════════════════════

  defp build_alerts(issues, stale_tasks) do
    issue_alerts =
      Enum.map(issues, fn issue ->
        %{
          severity: String.downcase(issue.severity),
          message: issue.description,
          action: if(issue.type in ["dead_agent", "stale_task"], do: "heal_task"),
          action_label: "Reset",
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

  defp role_badge_class(role) when is_binary(role) do
    cond do
      String.contains?(role, "lead") -> "bg-violet/20 text-violet"
      String.contains?(role, "coordinator") -> "bg-brand/20 text-brand"
      String.contains?(role, "worker") -> "bg-cyan/20 text-cyan"
      true -> "bg-highlight text-default"
    end
  end

  defp role_badge_class(_), do: "bg-highlight text-default"

  defp status_sort_val(:active), do: 0
  defp status_sort_val(:idle), do: 1
  defp status_sort_val(_), do: 2

  defp short_model(nil), do: ""

  defp short_model(m) when is_binary(m) do
    cond do
      String.contains?(m, "opus") -> "opus"
      String.contains?(m, "sonnet") -> "sonnet"
      String.contains?(m, "haiku") -> "haiku"
      true -> String.slice(m, 0, 8)
    end
  end

  defp status_dot_color(status), do: member_status_dot_class(status)
  defp status_text_color(status), do: member_status_text_class(status)
  defp severity_color(severity), do: severity_bg_class(severity)
  defp severity_text_color(severity), do: severity_text_class(severity)
  defp task_status_color(status), do: task_status_text_class(status)

  defp activity_icon(:tool), do: "text-cyan"
  defp activity_icon(:error), do: "text-error"
  defp activity_icon(:notify), do: "text-violet"
  defp activity_icon(:task_done), do: "text-success"
  defp activity_icon(_), do: "text-low"

  defp activity_label(:tool, act), do: act.tool
  defp activity_label(:error, act), do: "#{act.tool}!"
  defp activity_label(:notify, _act), do: "msg"
  defp activity_label(:task_done, _act), do: "done"
  defp activity_label(_, _act), do: "?"

  defp format_health_issue(:stuck), do: "stuck"
  defp format_health_issue(:looping), do: "looping"
  defp format_health_issue(:high_failure_rate), do: "high fail"
  defp format_health_issue(other), do: to_string(other)
end
