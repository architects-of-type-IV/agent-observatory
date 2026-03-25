defmodule IchorWeb.SignalFeed.Renderers.Agent do
  @moduledoc """
  Renders signals in the agent and fleet topic namespaces.
  Covers agent lifecycle, nudge escalation, team events, and memory.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: "fleet.agent.started", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "fleet.agent.stopped", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "agent.crashed", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "fleet.agent.paused", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium"><span class="font-mono">{@sid}</span> paused</span>
    """
  end

  def render(%{event: %Event{topic: "fleet.agent.resumed", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium"><span class="font-mono">{@sid}</span> resumed</span>
    """
  end

  def render(%{event: %Event{topic: "fleet.agent.evicted", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">
      <span class="font-mono">{@sid}</span> evicted (heartbeat timeout)
    </span>
    """
  end

  def render(%{event: %Event{topic: "fleet.agent.reaped", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">
      <span class="font-mono">{@sid}</span> reaped (tmux dead)
    </span>
    """
  end

  def render(%{event: %Event{topic: "fleet.agent.discovered", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">discovered <span class="font-mono">{@sid}</span></span>
    """
  end

  def render(%{event: %Event{topic: "agent.spawned", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "agent.nudge." <> _, data: data}} = assigns) do
    nudge_suffix = String.replace_prefix(assigns.event.topic, "agent.nudge.", "")

    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        level: to_string(data[:level] || "?"),
        label: nudge_label(nudge_suffix)
      )

    ~H"""
    <span class="text-[10px] text-brand font-medium">{@label}</span>
    <span class="font-mono text-[10px]">{@sid}</span>
    <Primitives.kv key="level" value={@level} />
    """
  end

  def render(%{event: %Event{topic: "fleet.team.created", data: data}} = assigns) do
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

  def render(%{event: %Event{topic: "fleet.team.disbanded", data: data}} = assigns) do
    assigns = assign(assigns, name: to_string(data[:team_name] || "?"))

    ~H"""
    <span class="text-[10px] text-medium">
      team <span class="font-semibold">{@name}</span> disbanded
    </span>
    """
  end

  def render(%{event: %Event{topic: "fleet.registry.changed"}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">fleet state changed</span>
    """
  end

  def render(%{event: %Event{topic: "fleet.hosts.changed"}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">cluster topology changed</span>
    """
  end

  def render(%{event: %Event{topic: "team.tasks.updated", data: data}} = assigns) do
    assigns = assign(assigns, team: data[:team_name])

    ~H"""
    <span class="text-[10px] text-muted">tasks updated{if @team, do: " for #{@team}", else: ""}</span>
    """
  end

  def render(%{event: %Event{topic: "agent.event", data: data}} = assigns) do
    event = data[:event] || %{}

    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id] || data[:scope_id]),
        kind: to_string(event[:kind] || event[:type] || event[:name] || "event")
      )

    ~H"""
    <span class="text-[10px] text-muted">event</span>
    <Primitives.kv :if={@sid != "?"} key="sid" value={@sid} />
    <Primitives.kv key="kind" value={@kind} />
    """
  end

  def render(%{event: %Event{topic: "agent.message.intercepted", data: data}} = assigns) do
    assigns =
      assign(assigns,
        from: Primitives.short(data[:from]),
        to: Primitives.short(data[:to]),
        type: to_string(data[:type] || "msg")
      )

    ~H"""
    <span class="text-[10px] text-muted">intercepted</span>
    <span class="font-mono text-[9px] text-muted">{@from} -> {@to}</span>
    <Primitives.kv key="type" value={@type} />
    """
  end

  def render(%{event: %Event{topic: "agent.terminal.output", data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id] || data[:scope_id]))

    ~H"""
    <span class="text-[10px] text-muted font-mono">tmux</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{event: %Event{topic: "agent.mailbox.message", data: data}} = assigns) do
    msg = data[:message] || %{}

    assigns =
      assign(assigns,
        sid: Primitives.short(data[:scope_id]),
        from: Primitives.short(msg[:from] || msg["from"])
      )

    ~H"""
    <span class="text-[10px] text-default">mailbox</span>
    <Primitives.kv :if={@from != "?"} key="from" value={@from} />
    <Primitives.kv :if={@sid != "?"} key="to" value={@sid} />
    """
  end

  def render(%{event: %Event{topic: "agent.instructions", data: data}} = assigns) do
    assigns =
      assign(assigns,
        cls: to_string(data[:agent_class] || "?"),
        sid: Primitives.short(data[:scope_id])
      )

    ~H"""
    <span class="text-[10px] text-default">instructions</span>
    <Primitives.kv key="class" value={@cls} />
    <Primitives.kv :if={@sid != "?"} key="sid" value={@sid} />
    """
  end

  def render(%{event: %Event{topic: "agent.scheduled_job", data: data}} = assigns) do
    assigns = assign(assigns, agent_id: Primitives.short(data[:agent_id]))

    ~H"""
    <span class="text-[10px] text-muted">scheduled job fired</span>
    <Primitives.kv key="agent" value={@agent_id} />
    """
  end

  def render(%{event: %Event{topic: topic, data: data}} = assigns) do
    assigns =
      assign(assigns,
        topic: topic,
        pairs: data_to_pairs(data)
      )

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@topic}</span>
    <span :for={p <- @pairs} class="mr-1">
      <Primitives.kv key={p.key} value={p.val} />
    </span>
    """
  end

  defp data_to_pairs(nil), do: []

  defp data_to_pairs(data) when is_map(data) do
    data
    |> Enum.map(fn {k, v} -> %{key: to_string(k), val: format_val(v)} end)
    |> Enum.sort_by(& &1.key)
  end

  defp data_to_pairs(_), do: []

  defp format_val(nil), do: "nil"
  defp format_val(v) when is_binary(v) and byte_size(v) > 60, do: String.slice(v, 0, 57) <> "..."
  defp format_val(v) when is_binary(v), do: v
  defp format_val(v) when is_atom(v), do: Atom.to_string(v)
  defp format_val(v) when is_number(v), do: to_string(v)
  defp format_val(v) when is_list(v), do: "[#{length(v)} items]"

  defp format_val(v) when is_map(v),
    do: inspect(v, limit: 3, pretty: false) |> String.slice(0, 60)

  defp format_val(v), do: inspect(v, limit: 3, printable_limit: 20) |> String.slice(0, 60)

  defp nudge_label("warning"), do: "warn"
  defp nudge_label("sent"), do: "nudge sent"
  defp nudge_label("escalated"), do: "escalated"
  defp nudge_label("zombie"), do: "zombie"
  defp nudge_label(other), do: other
end
