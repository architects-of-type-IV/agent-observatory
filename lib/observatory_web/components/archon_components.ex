defmodule ObservatoryWeb.Components.ArchonComponents do
  @moduledoc """
  Archon overlay: chat interface + shortcodes reference.
  Triggered by keyboard shortcut (a) or floating action button.

  Composed from sub-components for modularity.
  """

  use Phoenix.Component

  @shortcodes [
    {"agents", "List all agents in the fleet"},
    {"teams", "List all active teams"},
    {"status <agent>", "Check an agent's status"},
    {"msg <target> <text>", "Send a message to an agent or team"},
    {"inbox", "Show recent messages"},
    {"health", "System health check"},
    {"sessions", "List tmux sessions"},
    {"remember <text>", "Persist an observation to memory"},
    {"recall <query>", "Search knowledge graph"},
    {"query <question>", "Natural language memory query"}
  ]

  # ── Main overlay ──────────────────────────────────────────────────────

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false

  def archon_overlay(assigns) do
    assigns = assign(assigns, :shortcodes, @shortcodes)

    ~H"""
    <div class="archon-overlay" phx-click="archon_close">
      <div class="archon-backdrop" />
      <div class="archon-panel" phx-click="stop">
        <.shortcodes_panel shortcodes={@shortcodes} />
        <.chat_panel messages={@messages} loading={@loading} />
      </div>
    </div>
    """
  end

  # ── FAB (floating action button) ──────────────────────────────────────

  attr :show_archon, :boolean, default: false

  def archon_fab(assigns) do
    ~H"""
    <button
      phx-click="archon_toggle"
      class={["archon-fab group", if(@show_archon, do: "archon-fab-active", else: "archon-fab-idle")]}
      title="Archon (a)"
    >
      <.archon_icon active={@show_archon} />
    </button>
    """
  end

  # ── Sub-components ────────────────────────────────────────────────────

  attr :shortcodes, :list, required: true

  defp shortcodes_panel(assigns) do
    ~H"""
    <div class="archon-sidebar">
      <div class="archon-header">
        <h3 class="obs-section-title text-amber-500/80">Shortcodes</h3>
      </div>
      <div class="flex-1 overflow-y-auto p-3 space-y-1">
        <.shortcode_item :for={{cmd, desc} <- @shortcodes} cmd={cmd} desc={desc} />
      </div>
    </div>
    """
  end

  attr :cmd, :string, required: true
  attr :desc, :string, required: true

  defp shortcode_item(assigns) do
    ~H"""
    <div class="archon-shortcode" phx-click="archon_shortcode" phx-value-cmd={@cmd}>
      <code class="archon-shortcode-cmd">/{@cmd}</code>
      <p class="archon-shortcode-desc">{@desc}</p>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false

  defp chat_panel(assigns) do
    ~H"""
    <div class="archon-chat">
      <.chat_header />
      <.chat_messages messages={@messages} loading={@loading} />
      <.chat_input />
    </div>
    """
  end

  defp chat_header(assigns) do
    ~H"""
    <div class="archon-header">
      <div class="flex items-center gap-2">
        <div class="archon-dot" />
        <h2 class="archon-title">Archon</h2>
        <span class="archon-subtitle">sovereign agent</span>
      </div>
      <div class="flex items-center gap-2">
        <kbd class="px-1.5 py-0.5 bg-zinc-800 border border-zinc-700 rounded text-[10px] text-zinc-500 font-mono">
          a
        </kbd>
        <button phx-click="archon_close" class="text-zinc-500 hover:text-zinc-300 transition">
          <svg class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
            <path
              fill-rule="evenodd"
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false

  defp chat_messages(assigns) do
    ~H"""
    <div id="archon-messages" class="archon-messages" phx-hook="ScrollBottom">
      <.empty_state :if={@messages == []} />
      <.chat_bubble :for={msg <- @messages} role={msg.role} content={msg.content} />
      <.typing_indicator :if={@loading} />
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="obs-empty h-full">
      <div class="archon-empty-icon">
        <svg class="w-12 h-12 mx-auto" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1">
          <path d="M12 2L2 7l10 5 10-5-10-5zM2 17l10 5 10-5M2 12l10 5 10-5" />
        </svg>
      </div>
      <p class="obs-empty-title">Archon is ready.</p>
      <p class="obs-empty-desc">Type a message or use a shortcode.</p>
    </div>
    """
  end

  attr :role, :atom, required: true
  attr :content, :string, required: true

  defp chat_bubble(assigns) do
    ~H"""
    <div class={["archon-msg", role_class(@role)]}>
      <div class={["archon-bubble", bubble_class(@role)]}>
        <div class="whitespace-pre-wrap">{@content}</div>
      </div>
      <div class={["archon-meta", meta_class(@role)]}>{@role}</div>
    </div>
    """
  end

  defp typing_indicator(assigns) do
    ~H"""
    <div class="archon-msg">
      <div class="archon-bubble archon-bubble-assistant">
        <div class="flex items-center gap-2 text-xs text-zinc-500">
          <div class="flex gap-1">
            <div class="archon-typing-dot" style="animation-delay: 0ms" />
            <div class="archon-typing-dot" style="animation-delay: 150ms" />
            <div class="archon-typing-dot" style="animation-delay: 300ms" />
          </div>
          <span>thinking</span>
        </div>
      </div>
    </div>
    """
  end

  defp chat_input(assigns) do
    ~H"""
    <div class="archon-input-area">
      <div id="archon-input-stable" phx-update="ignore">
        <form id="archon-chat-form" phx-submit="archon_send" phx-hook="ClearFormOnSubmit" class="flex gap-2">
          <input type="text" name="content" autocomplete="off" placeholder="Talk to Archon..." class="archon-input" />
          <button type="submit" class="archon-send-btn">Send</button>
        </form>
      </div>
    </div>
    """
  end

  attr :active, :boolean, default: false

  defp archon_icon(assigns) do
    ~H"""
    <svg
      class={["archon-fab-icon", if(@active, do: "archon-fab-icon-active", else: "archon-fab-icon-idle")]}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
    >
      <path d="M12 2L2 7l10 5 10-5-10-5z" />
      <path d="M2 17l10 5 10-5" />
      <path d="M2 12l10 5 10-5" />
    </svg>
    """
  end

  # ── Style helpers ─────────────────────────────────────────────────────

  defp role_class(:user), do: "archon-msg-user"
  defp role_class(_), do: ""

  defp bubble_class(:user), do: "archon-bubble-user"
  defp bubble_class(_), do: "archon-bubble-assistant"

  defp meta_class(:user), do: "archon-meta-user"
  defp meta_class(_), do: "archon-meta-assistant"
end
