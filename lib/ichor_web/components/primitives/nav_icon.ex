defmodule IchorWeb.Components.Primitives.NavIcon do
  @moduledoc """
  Primitive nav icon button for the left sidebar navigation.

  Encapsulates the repeated patch-link pattern: fixed size, tooltip,
  active/inactive color states.
  """

  use Phoenix.Component

  @doc """
  Renders a navigation icon link for the left sidebar.

  ## Examples

      <.nav_icon patch="/" label="Pipeline" active={@nav_view == :pipeline}>
        <svg ...>...</svg>
      </.nav_icon>
  """
  attr :patch, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def nav_icon(assigns) do
    ~H"""
    <.link
      patch={@patch}
      class={[
        "ichor-tip ichor-tip-right flex items-center justify-center w-7 h-7 rounded transition",
        if(@active,
          do: "bg-interactive/20 text-interactive",
          else: "text-muted hover:text-default hover:bg-raised"
        )
      ]}
      data-tip={@label}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
