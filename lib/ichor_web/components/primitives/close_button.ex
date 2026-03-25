defmodule IchorWeb.Components.Primitives.CloseButton do
  @moduledoc """
  Reusable close/dismiss button with consistent SVG X icon and hover styling.
  Used in detail panels, slideouts, and selection panels.
  """

  use Phoenix.Component

  @doc """
  Renders a small X button that fires a phx-click event.

  The button uses the SVG X icon from modal_components for visual consistency.
  Applies `text-muted hover:text-high transition` base styling, which can be
  extended via the `class` attr.
  """
  attr :on_click, :string, required: true
  attr :phx_target, :any, default: nil
  attr :class, :string, default: ""

  def close_button(assigns) do
    ~H"""
    <button
      phx-click={@on_click}
      phx-target={@phx_target}
      class={["text-muted hover:text-high transition p-0.5", @class]}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-4 w-4"
        viewBox="0 0 20 20"
        fill="currentColor"
      >
        <path
          fill-rule="evenodd"
          d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
          clip-rule="evenodd"
        />
      </svg>
    </button>
    """
  end
end
