defmodule ObservatoryWeb.Components.Observatory.EmptyState do
  @moduledoc """
  Renders an empty state with icon and guidance text.
  """

  use Phoenix.Component

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
    <div class="flex flex-col items-center justify-center py-24 text-zinc-600">
      <p class="text-lg">{@title}</p>
      <p class="text-sm mt-1 text-zinc-700">{@description}</p>
    </div>
    """
  end
end
