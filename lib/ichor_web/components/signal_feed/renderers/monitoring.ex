defmodule IchorWeb.SignalFeed.Renderers.Monitoring do
  @moduledoc """
  Renders signals in the monitoring and team topic namespaces.
  Covers quality gates, agent status, task events, and watchdog.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: "monitoring.gate.passed", data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        task_id: Primitives.short(data[:task_id])
      )

    ~H"""
    <span class="text-[10px] text-success">gate passed</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv :if={@task_id != "?"} key="task" value={@task_id} />
    """
  end

  def render(%{event: %Event{topic: "monitoring.gate.failed", data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        task_id: Primitives.short(data[:task_id])
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">gate failed</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv :if={@task_id != "?"} key="task" value={@task_id} />
    """
  end

  def render(%{event: %Event{topic: "monitoring.agent.done", data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        summary: Primitives.truncate(to_string(data[:summary] || ""), 40)
      )

    ~H"""
    <span class="text-[10px] text-success">done</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <span :if={@summary != ""} class="text-[10px] text-default ml-1">{@summary}</span>
    """
  end

  def render(%{event: %Event{topic: "monitoring.agent.blocked", data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        reason: Primitives.truncate(to_string(data[:reason] || "?"), 40)
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">blocked</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{event: %Event{topic: "monitoring.protocol.update", data: data}} = assigns) do
    stats = data[:stats_map] || %{}

    assigns =
      assign(assigns,
        agents: stats[:agent_count] || stats["agent_count"],
        sessions: stats[:session_count] || stats["session_count"]
      )

    ~H"""
    <span class="text-[10px] text-muted">protocol stats updated</span>
    <Primitives.kv :if={@agents} key="agents" value={to_string(@agents)} />
    <Primitives.kv :if={@sessions} key="sessions" value={to_string(@sessions)} />
    """
  end

  def render(%{event: %Event{topic: "monitoring.watchdog.sweep", data: data}} = assigns) do
    assigns =
      assign(assigns,
        orphaned: to_string(data[:orphaned_count] || 0),
        orphaned_count: data[:orphaned_count] || 0
      )

    ~H"""
    <span class="text-[10px] text-muted">watchdog sweep</span>
    <Primitives.kv
      :if={@orphaned_count > 0}
      key="orphaned"
      value={@orphaned}
    />
    """
  end

  def render(%{event: %Event{topic: "team.task.created", data: data}} = assigns) do
    task = data[:task] || %{}

    assigns =
      assign(assigns,
        subject: Primitives.truncate(to_string(task[:subject] || task["subject"] || "?"), 40)
      )

    ~H"""
    <span class="text-[10px] text-default">task created:</span>
    <span class="text-[10px] text-high">{@subject}</span>
    """
  end

  def render(%{event: %Event{topic: "team.task.updated", data: data}} = assigns) do
    task = data[:task] || %{}

    assigns =
      assign(assigns,
        subject: Primitives.truncate(to_string(task[:subject] || task["subject"] || "?"), 30),
        status: to_string(task[:status] || task["status"] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">task updated:</span>
    <span class="text-[10px] text-high">{@subject}</span>
    <Primitives.kv key="status" value={@status} />
    """
  end

  def render(%{event: %Event{topic: "team.task.deleted", data: data}} = assigns) do
    assigns = assign(assigns, task_id: Primitives.short(data[:task_id]))

    ~H"""
    <span class="text-[10px] text-muted">task deleted</span>
    <Primitives.kv key="id" value={@task_id} />
    """
  end

  def render(%{event: %Event{topic: topic, data: data}} = assigns) do
    assigns =
      assign(assigns,
        topic: topic,
        pairs: Primitives.data_to_pairs(data)
      )

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@topic}</span>
    <span :for={p <- @pairs} class="mr-1">
      <Primitives.kv key={p.key} value={p.val} />
    </span>
    """
  end
end
