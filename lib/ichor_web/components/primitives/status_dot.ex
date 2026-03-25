defmodule IchorWeb.Components.Primitives.StatusDot do
  @moduledoc """
  Primitive dot component for inline status indicators.

  Accepts a raw Tailwind color class (e.g. "bg-success", "bg-error").
  For semantic atom-based status dots, use `member_status_dot` instead.
  """

  use Phoenix.Component

  @doc """
  Renders a small filled circle dot.

  ## Examples

      <.status_dot color="bg-success" />
      <.status_dot color="bg-error" size="w-2 h-2" />
  """
  attr :color, :string, required: true
  attr :size, :string, default: "w-1.5 h-1.5"
  attr :class, :string, default: ""

  def status_dot(assigns) do
    ~H"""
    <span class={"rounded-full shrink-0 #{@size} #{@color} #{@class}"} />
    """
  end
end
