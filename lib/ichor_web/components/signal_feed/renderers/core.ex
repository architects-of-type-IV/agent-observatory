defmodule IchorWeb.SignalFeed.Renderers.Core do
  @moduledoc """
  Renders signals in the :system, :events, :messages, and :memory domains.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :message, :any, required: true

  def render(%{message: %Message{name: :heartbeat, data: data}} = assigns) do
    assigns = assign(assigns, count: data[:count] || "?")

    ~H"""
    <span class="text-[10px] text-muted">beat <span class="font-mono">#{@count}</span></span>
    """
  end

  def render(%{message: %Message{name: :registry_changed}} = assigns) do
    ~H"""
    <span class="text-[10px] text-muted">registry changed</span>
    """
  end

  def render(%{message: %Message{name: :dashboard_command, data: data}} = assigns) do
    assigns = assign(assigns, cmd: to_string(data[:command] || "?"))

    ~H"""
    <span class="text-[10px] text-default">command: <span class="font-mono">{@cmd}</span></span>
    """
  end

  def render(%{message: %Message{name: :new_event}} = assigns) do
    ~H"""
    <span class="text-[10px] text-success">hook event ingested</span>
    """
  end

  def render(%{message: %Message{name: :message_delivered, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :block_changed, data: data}} = assigns) do
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

  def render(%{message: %Message{name: :memory_changed, data: data}} = assigns) do
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

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono">{@message.name}</span>
    """
  end

  defp truncate(s, max) when byte_size(s) > max, do: String.slice(s, 0, max - 2) <> ".."
  defp truncate(s, _max), do: s
end
