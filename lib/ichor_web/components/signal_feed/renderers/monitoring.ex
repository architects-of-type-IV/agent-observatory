defmodule IchorWeb.SignalFeed.Renderers.Monitoring do
  @moduledoc """
  Renders signals in the :monitoring and :team domains.
  Covers quality gates, agent status, task events, and watchdog.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :gate_passed, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :gate_failed, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :agent_done, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        summary: truncate(to_string(data[:summary] || ""), 40)
      )

    ~H"""
    <span class="text-[10px] text-success">done</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <span :if={@summary != ""} class="text-[10px] text-default ml-1">{@summary}</span>
    """
  end

  def render(%{message: %Message{name: :agent_blocked, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        reason: truncate(to_string(data[:reason] || "?"), 40)
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">blocked</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :protocol_update}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">protocol stats updated</span>
    """
  end

  def render(%{message: %Message{name: :watchdog_sweep, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :task_created, data: data}} = assigns) do
    task = data[:task] || %{}

    assigns =
      assign(assigns, subject: truncate(to_string(task[:subject] || task["subject"] || "?"), 40))

    ~H"""
    <span class="text-[10px] text-default">task created:</span>
    <span class="text-[10px] text-high">{@subject}</span>
    """
  end

  def render(%{message: %Message{name: :task_updated, data: data}} = assigns) do
    task = data[:task] || %{}

    assigns =
      assign(assigns,
        subject: truncate(to_string(task[:subject] || task["subject"] || "?"), 30),
        status: to_string(task[:status] || task["status"] || "?")
      )

    ~H"""
    <span class="text-[10px] text-default">task updated:</span>
    <span class="text-[10px] text-high">{@subject}</span>
    <Primitives.kv key="status" value={@status} />
    """
  end

  def render(%{message: %Message{name: :task_deleted, data: data}} = assigns) do
    assigns = assign(assigns, task_id: Primitives.short(data[:task_id]))

    ~H"""
    <span class="text-[10px] text-muted">task deleted</span>
    <Primitives.kv key="id" value={@task_id} />
    """
  end

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono">{@message.name}</span>
    """
  end

  defp truncate(s, max) when byte_size(s) > max, do: String.slice(s, 0, max - 2) <> ".."
  defp truncate(s, _max), do: s
end
