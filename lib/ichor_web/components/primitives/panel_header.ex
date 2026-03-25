defmodule IchorWeb.Components.Primitives.PanelHeader do
  @moduledoc """
  Reusable panel section header: border-b container with a title and optional right-side slot.
  """

  use Phoenix.Component

  @doc """
  Renders a standard panel header with a title and optional right-side actions.

  ## Examples

      <.panel_header title="Fleet" />

      <.panel_header title="Pipeline Board">
        <:actions>
          <span class="text-[9px] text-muted">42 agents</span>
        </:actions>
      </.panel_header>
  """
  attr :title, :string, required: true
  attr :class, :string, default: ""

  slot :actions

  def panel_header(assigns) do
    ~H"""
    <div class={"px-3 py-1.5 border-b border-border flex items-center justify-between shrink-0 " <> @class}>
      <span class="ichor-section-title">{@title}</span>
      <%= render_slot(@actions) %>
    </div>
    """
  end
end
