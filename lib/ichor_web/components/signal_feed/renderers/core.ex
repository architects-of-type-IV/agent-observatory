defmodule IchorWeb.SignalFeed.Renderers.Core do
  @moduledoc """
  Renders signals in the system, events, messages, and memory topic namespaces.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: "system.heartbeat", data: data}} = assigns) do
    assigns = assign(assigns, count: data[:count] || "?")

    ~H"""
    <span class="text-[10px] text-muted">beat <span class="font-mono">#{@count}</span></span>
    """
  end

  def render(%{event: %Event{topic: "system.registry.changed"}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">registry changed</span>
    """
  end

  def render(%{event: %Event{topic: "system.dashboard.command", data: data}} = assigns) do
    assigns = assign(assigns, cmd: to_string(data[:command] || "?"))

    ~H"""
    <span class="text-[10px] text-default">command: <span class="font-mono">{@cmd}</span></span>
    """
  end

  def render(%{event: %Event{topic: "events.hook.ingested"}} = assigns) do
    ~H"""
    <span class="text-[10px] text-success">hook event ingested</span>
    """
  end

  def render(%{event: %Event{topic: "messages.delivered", data: data}} = assigns) do
    msg = data[:msg_map] || %{}

    assigns =
      assign(assigns,
        from: Primitives.short(msg[:from] || msg["from"]),
        to: Primitives.short(msg[:to] || msg["to"]),
        content: truncate(msg[:content] || msg["content"] || "", 50)
      )

    ~H"""
    <span class="font-mono text-[9px] text-muted">{@from}</span>
    <span class="text-[9px] text-muted mx-0.5">-></span>
    <span class="font-mono text-[9px] text-muted">{@to}</span>
    <span class="text-[10px] text-default ml-1">{@content}</span>
    """
  end

  def render(%{event: %Event{topic: "memory.block.changed", data: data}} = assigns) do
    assigns =
      assign(assigns,
        block_id: Primitives.short(data[:block_id]),
        label: data[:label]
      )

    ~H"""
    <span class="text-[10px] text-medium">
      block <span class="font-mono">{@block_id}</span> modified
    </span>
    <Primitives.kv :if={@label} key="label" value={to_string(@label)} />
    """
  end

  def render(%{event: %Event{topic: "memory.changed", data: data}} = assigns) do
    assigns =
      assign(assigns,
        agent: data[:agent_name],
        event: data[:event]
      )

    ~H"""
    <span class="text-[10px] text-medium">memory changed</span>
    <Primitives.kv :if={@agent} key="agent" value={to_string(@agent)} />
    <Primitives.kv :if={@event} key="event" value={to_string(@event)} />
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

  defp truncate(s, max) when byte_size(s) > max, do: String.slice(s, 0, max - 2) <> ".."
  defp truncate(s, _max), do: s
end
