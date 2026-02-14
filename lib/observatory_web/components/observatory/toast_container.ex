defmodule ObservatoryWeb.Components.Observatory.ToastContainer do
  @moduledoc """
  Renders a toast notification container.
  """

  use Phoenix.Component

  @doc """
  Renders a toast notification container.

  ## Examples

      <.toast_container />
  """
  def toast_container(assigns) do
    ~H"""
    <div
      id="toast-container"
      phx-hook="Toast"
      class="fixed top-4 right-4 z-50 flex flex-col gap-2 pointer-events-none"
    >
    </div>
    """
  end
end
