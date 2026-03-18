defmodule IchorWeb.Components.ArchonComponents.Toast do
  @moduledoc false

  use Phoenix.Component

  attr :toasts, :list, default: []

  def toast_stack(assigns) do
    ~H"""
    <div class="ichor-toast-stack" aria-live="polite">
      <div
        :for={toast <- @toasts}
        id={"toast-#{toast.id}"}
        class={"ichor-toast ichor-toast-#{toast.level}"}
        phx-click="dismiss_toast"
        phx-value-id={toast.id}
      >
        <div class="ichor-toast-accent" />
        <div class="ichor-toast-body">
          <span class="ichor-toast-label">{level_label(toast.level)}</span>
          <span class="ichor-toast-msg">{toast.msg}</span>
        </div>
        <button class="ichor-toast-dismiss" aria-label="dismiss">&times;</button>
      </div>
    </div>
    """
  end

  defp level_label(:info), do: "INFO"
  defp level_label(:warning), do: "WARN"
  defp level_label(:error), do: "ERR"
  defp level_label(_), do: "SYS"
end
