defmodule ObservatoryWeb.Components.ArchonComponents do
  @moduledoc """
  Archon: sovereign agent control interface.
  Type IV command HUD with quick actions, chat, and shortcode reference.
  """

  use Phoenix.Component

  @quick_actions [
    %{key: "1", cmd: "agents", label: "Agents", icon: "grid", desc: "List fleet"},
    %{key: "2", cmd: "teams", label: "Teams", icon: "layers", desc: "Active teams"},
    %{key: "3", cmd: "inbox", label: "Inbox", icon: "mail", desc: "Messages"},
    %{key: "4", cmd: "health", label: "Health", icon: "pulse", desc: "System check"},
    %{key: "5", cmd: "sessions", label: "Sessions", icon: "terminal", desc: "Tmux"},
    %{key: "6", cmd: "recall", label: "Recall", icon: "search", desc: "Search memory"},
    %{key: "7", cmd: "query", label: "Query", icon: "brain", desc: "Ask memory"}
  ]

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
  attr :tab, :atom, default: :command

  def archon_overlay(assigns) do
    assigns =
      assigns
      |> assign(:shortcodes, @shortcodes)
      |> assign(:quick_actions, @quick_actions)

    ~H"""
    <div class="archon-overlay" phx-click="archon_close">
      <div class="archon-backdrop" />
      <div class="archon-panel" onclick="event.stopPropagation()">
        <%!-- Top bar --%>
        <div class="archon-topbar">
          <div class="flex items-center gap-3">
            <div class="archon-sigil" />
            <div>
              <h2 class="archon-title">ARCHON</h2>
              <p class="archon-subtitle">Type IV Sovereign Agent</p>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <div class="archon-status-row">
              <div class="archon-status-dot" />
              <span class="archon-status-text">ONLINE</span>
            </div>
            <div class="archon-tab-bar">
              <button phx-click="archon_set_tab" phx-value-tab="command"
                class={"archon-tab #{if @tab == :command, do: "archon-tab-active", else: ""}"}>
                <span class="archon-tab-key">Q</span> Command
              </button>
              <button phx-click="archon_set_tab" phx-value-tab="chat"
                class={"archon-tab #{if @tab == :chat, do: "archon-tab-active", else: ""}"}>
                <span class="archon-tab-key">W</span> Chat
              </button>
              <button phx-click="archon_set_tab" phx-value-tab="ref"
                class={"archon-tab #{if @tab == :ref, do: "archon-tab-active", else: ""}"}>
                <span class="archon-tab-key">E</span> Reference
              </button>
            </div>
            <button phx-click="archon_close" class="archon-close-btn">
              <kbd class="archon-kbd">esc</kbd>
            </button>
          </div>
        </div>

        <%!-- Content area --%>
        <div class="archon-content">
          <.command_hud :if={@tab == :command} actions={@quick_actions} loading={@loading} messages={@messages} />
          <.chat_panel :if={@tab == :chat} messages={@messages} loading={@loading} />
          <.reference_panel :if={@tab == :ref} shortcodes={@shortcodes} />
        </div>
      </div>
    </div>
    """
  end

  # ── FAB ──────────────────────────────────────────────────────────────

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

  # ── Command HUD (main tab) ─────────────────────────────────────────

  attr :actions, :list, required: true
  attr :loading, :boolean, default: false
  attr :messages, :list, default: []

  defp command_hud(assigns) do
    last_3 =
      assigns.messages
      |> Enum.reverse()
      |> Enum.take(3)
      |> Enum.reverse()

    assigns = assign(assigns, :recent, last_3)

    ~H"""
    <div class="flex h-full">
      <%!-- Quick Actions Grid --%>
      <div class="flex-1 p-5 flex flex-col">
        <div class="flex items-center justify-between mb-4">
          <h3 class="archon-section-title">Quick Actions</h3>
          <span class="text-[9px] text-amber-800/60 font-mono uppercase tracking-widest">Press key to execute</span>
        </div>
        <div class="grid grid-cols-4 gap-2.5 flex-1 content-start">
          <.action_card :for={action <- @actions} action={action} />
          <%!-- Free-form command slot --%>
          <div class="archon-action-card col-span-1 !border-dashed !border-zinc-800">
            <div class="flex items-center justify-between mb-1">
              <span class="archon-action-icon text-zinc-600"><.hud_icon name="command" /></span>
            </div>
            <div id="archon-quick-input" phx-update="ignore">
              <form phx-submit="archon_send" class="flex flex-col gap-1">
                <input type="text" name="content" autocomplete="off" placeholder="Free command..."
                  class="w-full bg-transparent border-0 border-b border-zinc-800 text-[11px] text-zinc-300 placeholder-zinc-700 p-0 pb-1 focus:outline-none focus:border-amber-800/50 focus:ring-0" />
              </form>
            </div>
          </div>
        </div>
      </div>

      <%!-- Activity feed (right strip) --%>
      <div class="w-56 border-l border-zinc-800/50 flex flex-col">
        <div class="px-3 py-3 border-b border-zinc-800/50">
          <h3 class="archon-section-title">Activity</h3>
        </div>
        <div class="flex-1 overflow-y-auto px-3 py-2 space-y-2">
          <%= if @recent == [] do %>
            <p class="text-[10px] text-zinc-700 italic mt-4 text-center">No activity yet.</p>
          <% else %>
            <.mini_bubble :for={msg <- @recent} role={msg.role} content={msg.content} />
          <% end %>
          <.typing_indicator :if={@loading} />
        </div>
        <div class="px-3 py-2 border-t border-zinc-800/50">
          <button phx-click="archon_set_tab" phx-value-tab="chat"
            class="w-full text-[10px] text-amber-600/70 hover:text-amber-500 font-mono uppercase tracking-wider text-center cursor-pointer transition">
            Open full chat ->
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :action, :map, required: true

  defp action_card(assigns) do
    ~H"""
    <div class="archon-action-card" phx-click="archon_shortcode" phx-value-cmd={@action.cmd}>
      <div class="flex items-center justify-between mb-1.5">
        <span class="archon-action-icon"><.hud_icon name={@action.icon} /></span>
        <kbd class="archon-action-key">{@action.key}</kbd>
      </div>
      <div class="archon-action-label">{@action.label}</div>
      <div class="archon-action-desc">{@action.desc}</div>
    </div>
    """
  end

  # ── Chat panel (tab) ───────────────────────────────────────────────

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false

  defp chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div id="archon-messages" class="archon-messages" phx-hook="ScrollBottom">
        <.empty_state :if={@messages == []} />
        <.chat_bubble :for={msg <- @messages} role={msg.role} content={msg.content} />
        <.typing_indicator :if={@loading} />
      </div>
      <div class="archon-input-area">
        <div id="archon-input-stable" phx-update="ignore">
          <form id="archon-chat-form" phx-submit="archon_send" phx-hook="ClearFormOnSubmit" class="flex gap-2">
            <input type="text" name="content" autocomplete="off" placeholder="Command Archon..." class="archon-input" />
            <button type="submit" class="archon-send-btn">Transmit</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ── Reference panel (tab) ──────────────────────────────────────────

  attr :shortcodes, :list, required: true

  defp reference_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="px-5 py-3 border-b border-zinc-800/50">
        <h3 class="archon-section-title">Command Reference</h3>
        <p class="text-[10px] text-zinc-600 mt-1">Click any command to execute immediately.</p>
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

  # ── Shared sub-components ──────────────────────────────────────────

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full opacity-40">
      <svg class="w-16 h-16 text-amber-600/30 mb-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="0.5">
        <circle cx="12" cy="12" r="10" />
        <path d="M12 2L2 7l10 5 10-5-10-5z" />
        <path d="M2 17l10 5 10-5" />
        <path d="M2 12l10 5 10-5" />
      </svg>
      <p class="text-xs text-zinc-600 font-mono uppercase tracking-widest">Awaiting command</p>
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
      <div class={["archon-meta", meta_class(@role)]}>{role_label(@role)}</div>
    </div>
    """
  end

  defp mini_bubble(assigns) do
    ~H"""
    <div class={["text-[10px] leading-relaxed", if(@role == :user, do: "text-right", else: "")]}>
      <div class={[
        "inline-block rounded px-2 py-1 max-w-full",
        case @role do
          :user -> "bg-amber-900/15 border border-amber-900/20 text-zinc-300"
          :system -> "bg-amber-950/30 border border-amber-700/20 text-amber-300/80"
          _ -> "bg-zinc-900/80 border border-zinc-800 text-zinc-400"
        end
      ]}>
        <div class="whitespace-pre-wrap line-clamp-3">{@content}</div>
      </div>
    </div>
    """
  end

  defp typing_indicator(assigns) do
    ~H"""
    <div class="archon-msg">
      <div class="archon-bubble archon-bubble-assistant">
        <div class="flex items-center gap-2 text-xs text-zinc-600">
          <div class="flex gap-1">
            <div class="archon-typing-dot" style="animation-delay: 0ms" />
            <div class="archon-typing-dot" style="animation-delay: 150ms" />
            <div class="archon-typing-dot" style="animation-delay: 300ms" />
          </div>
          <span class="font-mono text-[10px] uppercase tracking-wider">processing</span>
        </div>
      </div>
    </div>
    """
  end

  # ── HUD Icons ──────────────────────────────────────────────────────

  attr :name, :string, required: true

  defp hud_icon(%{name: "grid"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="3" y="3" width="7" height="7" /><rect x="14" y="3" width="7" height="7" />
      <rect x="3" y="14" width="7" height="7" /><rect x="14" y="14" width="7" height="7" />
    </svg>
    """
  end

  defp hud_icon(%{name: "layers"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M12 2L2 7l10 5 10-5-10-5z" /><path d="M2 17l10 5 10-5" /><path d="M2 12l10 5 10-5" />
    </svg>
    """
  end

  defp hud_icon(%{name: "mail"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="2" y="4" width="20" height="16" rx="2" /><path d="M22 4L12 13 2 4" />
    </svg>
    """
  end

  defp hud_icon(%{name: "pulse"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M3 12h4l3-9 4 18 3-9h4" />
    </svg>
    """
  end

  defp hud_icon(%{name: "terminal"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <rect x="2" y="3" width="20" height="18" rx="2" /><path d="M6 9l4 3-4 3" /><line x1="13" y1="15" x2="18" y2="15" />
    </svg>
    """
  end

  defp hud_icon(%{name: "search"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
    """
  end

  defp hud_icon(%{name: "brain"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M12 2a7 7 0 0 1 7 7c0 2.5-1.3 4.7-3.2 6H8.2C6.3 13.7 5 11.5 5 9a7 7 0 0 1 7-7z" />
      <path d="M9 22v-4h6v4" /><path d="M9 18h6" />
    </svg>
    """
  end

  defp hud_icon(%{name: "command"} = assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <path d="M18 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3 3 3 0 0 0-3-3H6a3 3 0 0 0-3 3 3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3 3 3 0 0 0-3 3 3 3 0 0 0 3 3h12a3 3 0 0 0 3-3 3 3 0 0 0-3-3z" />
    </svg>
    """
  end

  defp hud_icon(assigns) do
    ~H"""
    <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
      <circle cx="12" cy="12" r="10" />
    </svg>
    """
  end

  # ── Archon FAB icon ────────────────────────────────────────────────

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

  # ── Style helpers ─────────────────────────────────────────────────

  defp role_class(:user), do: "archon-msg-user"
  defp role_class(:system), do: "archon-msg-system"
  defp role_class(_), do: ""

  defp bubble_class(:user), do: "archon-bubble-user"
  defp bubble_class(:system), do: "archon-bubble-system"
  defp bubble_class(_), do: "archon-bubble-assistant"

  defp meta_class(:user), do: "archon-meta-user"
  defp meta_class(:system), do: "archon-meta-system"
  defp meta_class(_), do: "archon-meta-assistant"

  defp role_label(:system), do: "alert"
  defp role_label(:user), do: "architect"
  defp role_label(_), do: "archon"
end
