defmodule IchorWeb.Components.ModalComponents do
  @moduledoc """
  Reusable modal and overlay components.
  Generic modal wrapper + specific modal content components.
  """

  use Phoenix.Component

  @shortcuts [
    {"Navigation",
     [
       {"Switch views (1-6)", "1-6"},
       {"Focus search", "f"},
       {"Archon", "a"},
       {"Clear selection", "Esc"}
     ]},
    {"Feed",
     [
       {"Next event", "j"},
       {"Previous event", "k"}
     ]},
    {"Help",
     [
       {"Show this help", "?"}
     ]}
  ]

  # ── Generic modal wrapper ─────────────────────────────────────────────

  attr :show, :boolean, required: true
  attr :on_close, :string, required: true
  attr :max_width, :string, default: "max-w-lg"
  slot :header, required: true
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 bg-black/50 flex items-center justify-center z-50"
      phx-click={@on_close}
    >
      <div
        class={["bg-base border border-border-subtle rounded-lg shadow-xl w-full mx-4", @max_width]}
        phx-click="stop"
      >
        <div class="px-4 py-3 border-b border-border flex items-center justify-between">
          <h2 class="text-sm font-semibold text-high">{render_slot(@header)}</h2>
          <.close_button on_close={@on_close} />
        </div>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # ── Close button (reusable) ───────────────────────────────────────────

  attr :on_close, :string, required: true

  defp close_button(assigns) do
    ~H"""
    <button phx-click={@on_close} class="text-low hover:text-high transition">
      <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
        <path
          fill-rule="evenodd"
          d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
          clip-rule="evenodd"
        />
      </svg>
    </button>
    """
  end

  # ── Keyboard Shortcuts Modal ──────────────────────────────────────────

  attr :show, :boolean, required: true

  def shortcuts_modal(assigns) do
    assigns = assign(assigns, :shortcut_groups, @shortcuts)

    ~H"""
    <.modal show={@show} on_close="toggle_shortcuts_help" max_width="max-w-md">
      <:header>Keyboard Shortcuts</:header>
      <div class="px-4 py-3 space-y-3">
        <.shortcut_group :for={{title, keys} <- @shortcut_groups} title={title} keys={keys} />
      </div>
    </.modal>
    """
  end

  attr :title, :string, required: true
  attr :keys, :list, required: true

  defp shortcut_group(assigns) do
    ~H"""
    <div>
      <h3 class="text-xs font-semibold text-low uppercase tracking-wider mb-2">{@title}</h3>
      <div class="space-y-1 text-xs">
        <.shortcut_row :for={{label, key} <- @keys} label={label} key={key} />
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :key, :string, required: true

  defp shortcut_row(assigns) do
    ~H"""
    <div class="flex items-center justify-between">
      <span class="text-default">{@label}</span>
      <kbd class="px-2 py-0.5 bg-raised border border-border-subtle rounded text-high font-mono">
        {@key}
      </kbd>
    </div>
    """
  end
end
