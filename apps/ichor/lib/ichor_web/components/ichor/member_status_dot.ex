defmodule IchorWeb.Components.Ichor.MemberStatusDot do
  @moduledoc """
  Renders a status dot for team members.
  """

  use Phoenix.Component
  import IchorWeb.Presentation, only: [member_status_dot_class: 1]

  @doc """
  Renders a status dot for team members.

  ## Examples

      <.member_status_dot status={:active} />
      <.member_status_dot status={:idle} />
  """
  attr :status, :atom, required: true

  def member_status_dot(assigns) do
    ~H"""
    <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{member_status_dot_class(@status)}"}></span>
    """
  end
end
