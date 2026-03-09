defmodule IchorWeb.DashboardToast do
  @moduledoc """
  Toast notification helpers for DashboardLive.
  Replaces Phoenix put_flash with auto-dismissing, Noir-styled toasts.
  """

  import Phoenix.Component, only: [assign: 3]

  @dismiss_after 4_000

  def push_toast(socket, level, msg) do
    id = System.unique_integer([:positive])
    toast = %{id: id, level: level, msg: msg}
    toasts = socket.assigns.toasts ++ [toast]
    Process.send_after(self(), {:dismiss_toast, id}, @dismiss_after)
    assign(socket, :toasts, toasts)
  end

  def dismiss_toast(socket, id) do
    id = if is_binary(id), do: String.to_integer(id), else: id
    toasts = Enum.reject(socket.assigns.toasts, &(&1.id == id))
    assign(socket, :toasts, toasts)
  end
end
