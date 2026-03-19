defmodule IchorWeb.SignalFeed.Renderers.Gateway do
  @moduledoc """
  Renders signals in the :gateway, :hitl, and :mesh domains.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :decision_log, data: data}} = assigns) do
    log = data[:log]

    assigns =
      assign(assigns,
        from: Primitives.short(log && log.identity && log.identity.agent_id),
        to: Primitives.short(log && log.meta && log.meta.trace_id)
      )

    ~H"""
    <span class="text-[10px] text-cyan">routed</span>
    <span class="font-mono text-[9px] text-muted">{@from} -> {@to}</span>
    """
  end

  def render(%{message: %Message{name: :schema_violation, data: data}} = assigns) do
    event = data[:event_map] || %{}
    assigns = assign(assigns, name: event[:name] || event["name"] || "unknown")

    ~H"""
    <span class="text-[10px] text-error font-medium">schema violation</span>
    <Primitives.kv key="event" value={to_string(@name)} />
    """
  end

  def render(%{message: %Message{name: :node_state_update, data: data}} = assigns) do
    assigns =
      assign(assigns,
        agent_id: Primitives.short(data[:agent_id]),
        state: to_string(data[:state] || "?")
      )

    ~H"""
    <span class="text-[10px] text-cyan">topology update</span>
    <span class="font-mono text-[9px]">{@agent_id}</span>
    <Primitives.kv key="state" value={@state} />
    """
  end

  def render(%{message: %Message{name: :entropy_alert, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        score: to_string(data[:entropy_score] || "?")
      )

    ~H"""
    <span class="text-[10px] text-brand font-medium">entropy alert</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv key="score" value={@score} />
    """
  end

  def render(%{message: %Message{name: :topology_snapshot, data: data}} = assigns) do
    nodes = data[:nodes] || []
    assigns = assign(assigns, node_count: length(nodes))

    ~H"""
    <span class="text-[10px] text-cyan">topology snapshot</span>
    <Primitives.kv key="nodes" value={to_string(@node_count)} />
    """
  end

  def render(%{message: %Message{name: :capability_update}} = assigns) do
    ~H"""
    <span class="text-[10px] text-cyan">capability map updated</span>
    """
  end

  def render(%{message: %Message{name: :dead_letter, data: data}} = assigns) do
    delivery = data[:delivery] || %{}
    assigns = assign(assigns, target: Primitives.short(delivery[:to] || delivery["to"]))

    ~H"""
    <span class="text-[10px] text-error font-medium">dead letter</span>
    <span class="font-mono text-[9px]">{@target}</span>
    """
  end

  def render(%{message: %Message{name: :gateway_audit, data: data}} = assigns) do
    assigns =
      assign(assigns,
        envelope_id: Primitives.short(data[:envelope_id]),
        channel: to_string(data[:channel] || "?")
      )

    ~H"""
    <span class="text-[10px] text-muted">audit</span>
    <span class="font-mono text-[9px]">{@envelope_id}</span>
    <Primitives.kv key="ch" value={@channel} />
    """
  end

  def render(%{message: %Message{name: :mesh_pause, data: data}} = assigns) do
    assigns = assign(assigns, by: Primitives.short(data[:initiated_by]))

    ~H"""
    <span class="text-[10px] text-error font-medium">mesh paused</span>
    <Primitives.kv key="by" value={@by} />
    """
  end

  def render(%{message: %Message{name: :dag_delta, data: data}} = assigns) do
    assigns =
      assign(assigns,
        sid: Primitives.short(data[:session_id]),
        added: length(data[:added_nodes] || [])
      )

    ~H"""
    <span class="text-[10px] text-muted">DAG delta</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    <Primitives.kv key="+nodes" value={to_string(@added)} />
    """
  end

  def render(%{message: %Message{name: :gate_open, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-error">gate opened</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :gate_close, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-success">gate closed</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_auto_released, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-medium">auto-released</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_operator_approved, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-success font-medium">approved</span>
    <span class="font-mono text-[9px]">{@sid}</span>
    """
  end

  def render(%{message: %Message{name: :hitl_operator_rejected, data: data}} = assigns) do
    assigns = assign(assigns, sid: Primitives.short(data[:session_id]))

    ~H"""
    <span class="text-[10px] text-error font-medium">rejected</span>
    <span class="font-mono text-[9px]">{@sid}</span>
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
end
