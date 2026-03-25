defmodule IchorWeb.UI.Select do
  @moduledoc """
  Base select primitive. Applies the ichor-input class.
  """

  use Phoenix.Component

  attr :name, :string, default: nil
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(phx-change phx-hook phx-update id)

  slot :inner_block, required: true

  @doc "Renders an ichor-styled select element."
  def select(assigns) do
    ~H"""
    <select name={@name} class={"ichor-input #{@class}"} {@rest}>
      {render_slot(@inner_block)}
    </select>
    """
  end
end
