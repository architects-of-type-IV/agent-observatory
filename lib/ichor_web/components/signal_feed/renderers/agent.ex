defmodule IchorWeb.SignalFeed.Renderers.Agent do
  @moduledoc """
  Renders signals in the :agent and :fleet domains.
  Covers agent lifecycle, nudge escalation, team events, and memory.
  """
  use Phoenix.Component

  alias Ichor.Events.Message
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

  def render(%{message: %Message{name: :agent_event, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :agent_message_intercepted, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :terminal_output, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id] || data[:scope_id]))

    ~H"""
    <span class="text-[10px] text-muted font-mono">tmux</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :mailbox_message, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :agent_instructions, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :scheduled_job, data: data}} = assigns) do
    assigns = assign(assigns, agent_id: Primitives.short(data[:agent_id]))

    ~H"""
    <span class="text-[10px] text-muted">scheduled job fired</span>
    <Primitives.kv key="agent" value={@agent_id} />
    """
  end

  def render(%{message: %Message{data: data}} = assigns) do
    assigns = assign(assigns, :pairs, data_to_pairs(data))

    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">{@message.name}</span>
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

  defp nudge_label(:nudge_warning), do: "warn"
  defp nudge_label(:nudge_sent), do: "nudge sent"
  defp nudge_label(:nudge_escalated), do: "escalated"
  defp nudge_label(:nudge_zombie), do: "zombie"
end
