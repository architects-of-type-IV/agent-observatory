defmodule ObservatoryWeb.Components.Observatory.EventTypeBadge do
  @moduledoc """
  Renders an event type badge.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers

  @doc """
  Renders an event type badge.

  ## Examples

      <.event_type_badge type={event.hook_event_type} />
  """
  attr :type, :atom, required: true

  def event_type_badge(assigns) do
    assigns = assign(assigns, :badge_info, event_type_label(assigns.type))

    ~H"""
    <% {label, badge_class} = @badge_info %>
    <span class={"text-xs font-mono px-1.5 py-0 rounded shrink-0 #{badge_class}"}>
      {label}
    </span>
    """
  end
end
