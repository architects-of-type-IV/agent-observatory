defmodule IchorWeb.Components.Ichor.EmptyState do
  @moduledoc """
  Renders an empty state with icon and guidance text.
  Delegates to EmptyPanel with a generous vertical padding default.
  """

  use Phoenix.Component

  import IchorWeb.Components.Primitives.EmptyPanel

  @doc """
  Renders an empty state with icon and guidance text.

  ## Examples

      <.empty_state
        title="No tasks yet"
        description="Tasks will appear when agents use TaskCreate/TaskUpdate"
      />
  """
  attr :title, :string, required: true
  attr :description, :string, required: true

  def empty_state(assigns) do
    ~H"""
    <.empty_panel title={@title} description={@description} class="py-24" />
    """
  end
end
