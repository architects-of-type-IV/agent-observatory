defmodule IchorWeb.Components.ArchonComponents do
  @moduledoc """
  Archon: sovereign agent control interface.
  Type IV command HUD with quick actions, chat, and shortcode reference.
  """

  use Phoenix.Component

  import IchorWeb.Components.ArchonComponents.Icons, only: [archon_icon: 1]
  import IchorWeb.Components.ArchonComponents.CommandHud, only: [command_hud: 1]
  import IchorWeb.Components.ArchonComponents.ChatPanel, only: [chat_panel: 1]
  import IchorWeb.Components.ArchonComponents.ReferencePanel, only: [reference_panel: 1]

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
    <div class="archon-overlay">
      <div class="archon-backdrop" phx-click="archon_close" />
      <div class="archon-panel">
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
end
