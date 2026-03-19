defmodule IchorWeb.SignalFeed.Renderers.Agent do
  @moduledoc """
  Renders signals in the :agent and :fleet domains.
  Covers agent lifecycle, nudge escalation, team events, and memory.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :agent_started, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        role: to_string(data[:role] || "agent"),
        team: data[:team]
      )

    ~H"""
    <span class="text-[10px] text-high">
      <span class="font-mono">{@sid}</span> joined as {@role}{if @team, do: " in #{@team}", else: ""}
    </span>
    """
  end

  def render(%{message: %Message{name: :agent_stopped, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        reason: to_string(data[:reason] || "normal")
      )

    ~H"""
    <span class="text-[10px] text-medium"><span class="font-mono">{@sid}</span> stopped</span>
    <Primitives.kv key="reason" value={@reason} />
    """
  end

  def render(%{message: %Message{name: :agent_crashed, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        team: data[:team_name]
      )

    ~H"""
    <span class="text-[10px] text-error font-medium">
      <span class="font-mono">{@sid}</span> crashed{if @team, do: " in #{@team}", else: ""}
    </span>
    """
  end

  def render(%{message: %Message{name: :agent_paused, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium"><span class="font-mono">{@sid}</span> paused</span>
    """
  end

  def render(%{message: %Message{name: :agent_resumed, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium"><span class="font-mono">{@sid}</span> resumed</span>
    """
  end

  def render(%{message: %Message{name: :agent_evicted, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">
      <span class="font-mono">{@sid}</span> evicted (heartbeat timeout)
    </span>
    """
  end

  def render(%{message: %Message{name: :agent_reaped, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">
      <span class="font-mono">{@sid}</span> reaped (tmux dead)
    </span>
    """
  end

  def render(%{message: %Message{name: :agent_discovered, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">discovered <span class="font-mono">{@sid}</span></span>
    """
  end

  def render(%{message: %Message{name: :agent_spawned, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        name: data[:name],
        cap: data[:capability]
      )

    ~H"""
    <span class="text-[10px] text-high">spawned <span class="font-mono">{@sid}</span></span>
    <Primitives.kv :if={@name} key="name" value={to_string(@name)} />
    <Primitives.kv :if={@cap} key="cap" value={to_string(@cap)} />
    """
  end

  def render(%{message: %Message{name: name, data: data}} = assigns)
      when name in [:nudge_warning, :nudge_sent, :nudge_escalated, :nudge_zombie] do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        level: to_string(data[:level] || "?"),
        label: nudge_label(name)
      )

    ~H"""
    <span class="text-[10px] text-brand font-medium">{@label}</span>
    <span class="font-mono text-[10px]">{@sid}</span>
    <Primitives.kv key="level" value={@level} />
    """
  end

  def render(%{message: %Message{name: :team_created, data: data}} = assigns) do
    assigns =
      assign(assigns,
        name: to_string(data[:name] || "?"),
        project: data[:project]
      )

    ~H"""
    <span class="text-[10px] text-high">team <span class="font-semibold">{@name}</span> created</span>
    <Primitives.kv :if={@project} key="project" value={to_string(@project)} />
    """
  end

  def render(%{message: %Message{name: :team_disbanded, data: data}} = assigns) do
    assigns = assign(assigns, name: to_string(data[:team_name] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">
      team <span class="font-semibold">{@name}</span> disbanded
    </span>
    """
  end

  def render(%{message: %Message{name: :fleet_changed}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">fleet state changed</span>
    """
  end

  def render(%{message: %Message{name: :hosts_changed}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">cluster topology changed</span>
    """
  end

  def render(%{message: %Message{name: :tasks_updated, data: data}} = assigns) do
    assigns = assign(assigns, team: data[:team_name])

    ~H"""
    <span class="text-[10px] text-muted">tasks updated{if @team, do: " for #{@team}", else: ""}</span>
    """
  end

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono">{@message.name}</span>
    """
  end

  defp nudge_label(:nudge_warning), do: "warn"
  defp nudge_label(:nudge_sent), do: "nudge sent"
  defp nudge_label(:nudge_escalated), do: "escalated"
  defp nudge_label(:nudge_zombie), do: "zombie"
end
