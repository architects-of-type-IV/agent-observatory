defmodule IchorWeb.UI.Label do
  @moduledoc """
  Base label primitive. Applies the ichor-section-title text style: 10px, semibold, uppercase, low color.
  """

  use Phoenix.Component

  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(for)

  slot :inner_block, required: true

  @doc "Renders a muted uppercase label in the ichor section-title style."
  def label(assigns) do
    ~H"""
    <label
      class={"text-[10px] font-semibold text-low uppercase tracking-wider #{@class}"}
      {@rest}
    >
      {render_slot(@inner_block)}
    </label>
    """
  end
end
