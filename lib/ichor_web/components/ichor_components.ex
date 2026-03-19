defmodule IchorWeb.IchorComponents do
  @moduledoc """
  Reusable function components for the Ichor dashboard.
  Delegates to focused child modules in components/ichor/.
  """
  use Phoenix.Component

  defdelegate member_status_dot(assigns),
    to: IchorWeb.Components.Ichor.MemberStatusDot

  defdelegate empty_state(assigns), to: IchorWeb.Components.Ichor.EmptyState
  defdelegate health_warnings(assigns), to: IchorWeb.Components.Ichor.HealthWarnings
  defdelegate model_badge(assigns), to: IchorWeb.Components.Ichor.ModelBadge
  defdelegate session_identity(assigns), to: IchorWeb.Components.Ichor.SessionIdentity

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :class, :string, default: "ichor-select"
  attr :rest, :global
  slot :inner_block, required: true

  def stable_select(assigns) do
    ~H"""
    <div id={"#{@id}-stable"} phx-update="ignore">
      <select id={@id} name={@name} class={@class} {@rest}>
        {render_slot(@inner_block)}
      </select>
    </div>
    """
  end
end
