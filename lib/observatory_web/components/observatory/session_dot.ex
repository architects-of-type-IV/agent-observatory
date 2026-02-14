defmodule ObservatoryWeb.Components.Observatory.SessionDot do
  @moduledoc """
  Renders a session color dot.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers

  @doc """
  Renders a session color dot.

  ## Examples

      <.session_dot session_id={event.session_id} />
      <.session_dot session_id={event.session_id} ended={true} />
  """
  attr :session_id, :string, required: true
  attr :ended, :boolean, default: false
  attr :size, :string, default: "w-2 h-2"

  def session_dot(assigns) do
    assigns = assign(assigns, :color_classes, session_color(assigns.session_id))

    ~H"""
    <% {bg, _border, _text} = @color_classes %>
    <span class={"#{@size} rounded-full shrink-0 #{bg} #{if @ended, do: "opacity-30", else: ""}"}></span>
    """
  end
end
