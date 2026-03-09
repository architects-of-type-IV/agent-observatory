defmodule IchorWeb.Components.ArchonComponents.ReferencePanel do
  @moduledoc false

  use Phoenix.Component

  attr :shortcodes, :list, required: true

  def reference_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="px-5 py-3 border-b border-border/50">
        <h3 class="archon-section-title">Command Reference</h3>
        <p class="text-[10px] text-muted mt-1">Click any command to execute immediately.</p>
      </div>
      <div class="flex-1 overflow-y-auto p-5">
        <div class="grid grid-cols-2 gap-2">
          <div :for={{cmd, desc} <- @shortcodes}
            class="archon-ref-item" phx-click="archon_shortcode" phx-value-cmd={cmd}>
            <code class="archon-ref-cmd">/{cmd}</code>
            <p class="archon-ref-desc">{desc}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
