defmodule IchorWeb.UI.Input do
  @moduledoc """
  Base input primitive. Applies the ichor-input class with optional extras.
  """

  use Phoenix.Component

  attr :type, :string, default: "text"
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :class, :string, default: ""

  attr :rest, :global,
    include: ~w(phx-change phx-debounce phx-hook phx-update id autocomplete required)

  @doc "Renders an ichor-styled text input."
  def input(assigns) do
    ~H"""
    <input
      type={@type}
      name={@name}
      value={@value}
      placeholder={@placeholder}
      class={"ichor-input #{@class}"}
      {@rest}
    />
    """
  end
end
