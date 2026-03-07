defmodule ObservatoryWeb.ObservatoryComponents do
  @moduledoc """
  Reusable function components for the Observatory dashboard.
  Delegates to focused child modules in components/observatory/.
  """
  use Phoenix.Component

  defdelegate member_status_dot(assigns),
    to: ObservatoryWeb.Components.Observatory.MemberStatusDot

  defdelegate empty_state(assigns), to: ObservatoryWeb.Components.Observatory.EmptyState
  defdelegate health_warnings(assigns), to: ObservatoryWeb.Components.Observatory.HealthWarnings
  defdelegate model_badge(assigns), to: ObservatoryWeb.Components.Observatory.ModelBadge
  defdelegate message_thread(assigns), to: ObservatoryWeb.Components.Observatory.MessageThread

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :class, :string, default: "obs-select"
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
