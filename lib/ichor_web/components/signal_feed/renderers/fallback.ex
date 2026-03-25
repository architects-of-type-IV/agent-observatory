defmodule IchorWeb.SignalFeed.Renderers.Fallback do
  @moduledoc """
  Catch-all renderer for signals with no dedicated renderer.
  Displays the event topic and all data keys as kv badges.
  Never crashes regardless of signal shape.
  """
  use Phoenix.Component

  alias Ichor.Events.Event
  alias IchorWeb.SignalFeed.Primitives

  attr :seq, :integer, required: true
  attr :event, :any, required: true

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

  def render(assigns) do
    ~H"""
    <span class="text-[10px] text-muted font-mono mr-1">unknown</span>
    """
  end
end
