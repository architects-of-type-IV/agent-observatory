defmodule IchorWeb.SignalFeed.Renderer do
  @moduledoc """
  Top-level dispatcher for signal row rendering.
  Delegates to per-domain renderer modules based on message.domain.
  Each renderer returns a compact inline fragment suitable for a feed table row.
  """
  use Phoenix.Component

  alias Ichor.Signals.Message

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
  attr :message, :any, required: true

  def render(%{message: %Message{domain: domain}} = assigns)
      when domain in [:agent, :fleet] do
    Agent.render(assigns)
  end

  def render(%{message: %Message{domain: domain}} = assigns)
      when domain in [:system, :events, :messages, :memory] do
    Core.render(assigns)
  end

  def render(%{message: %Message{domain: :planning}} = assigns) do
    Genesis.render(assigns)
  end

  def render(%{message: %Message{domain: :pipeline}} = assigns) do
    Dag.render(assigns)
  end

  def render(%{message: %Message{domain: :mes}} = assigns) do
    Mes.render(assigns)
  end

  def render(%{message: %Message{domain: domain}} = assigns)
      when domain in [:monitoring, :team] do
    Monitoring.render(assigns)
  end

  def render(assigns) do
    Fallback.render(assigns)
  end
end
