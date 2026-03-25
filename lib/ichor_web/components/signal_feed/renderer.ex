defmodule IchorWeb.SignalFeed.Renderer do
  @moduledoc """
  Top-level dispatcher for signal row rendering.
  Delegates to per-domain renderer modules based on event.topic prefix.
  Each renderer returns a compact inline fragment suitable for a feed table row.
  """
  use Phoenix.Component

  alias Ichor.Events.Event

  alias IchorWeb.SignalFeed.Renderers.{
    Agent,
    Core,
    Dag,
    Fallback,
    Genesis,
    Mes,
    Monitoring
  }

  attr :seq, :integer, required: true
  attr :event, :any, required: true

  def render(%{event: %Event{topic: "agent." <> _}} = assigns), do: Agent.render(assigns)
  def render(%{event: %Event{topic: "fleet." <> _}} = assigns), do: Agent.render(assigns)

  def render(%{event: %Event{topic: "system." <> _}} = assigns), do: Core.render(assigns)
  def render(%{event: %Event{topic: "events." <> _}} = assigns), do: Core.render(assigns)
  def render(%{event: %Event{topic: "messages." <> _}} = assigns), do: Core.render(assigns)
  def render(%{event: %Event{topic: "memory." <> _}} = assigns), do: Core.render(assigns)

  def render(%{event: %Event{topic: "planning." <> _}} = assigns), do: Genesis.render(assigns)

  def render(%{event: %Event{topic: "pipeline." <> _}} = assigns), do: Dag.render(assigns)

  def render(%{event: %Event{topic: "mes." <> _}} = assigns), do: Mes.render(assigns)

  def render(%{event: %Event{topic: "monitoring." <> _}} = assigns),
    do: Monitoring.render(assigns)

  def render(%{event: %Event{topic: "team." <> _}} = assigns), do: Monitoring.render(assigns)

  def render(assigns), do: Fallback.render(assigns)
end
