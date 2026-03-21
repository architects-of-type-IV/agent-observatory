defmodule IchorWeb.Components.ArchonComponents do
  @moduledoc """
  Archon: sovereign agent control interface.
  Type IV command HUD with quick actions, chat, and shortcode reference.
  Floating panel with position/size controls matching the terminal panel pattern.
  """

  use Phoenix.Component

  alias Ichor.Archon.CommandManifest
  alias IchorWeb.Components.ArchonComponents.PanelHelpers

  import IchorWeb.Components.ArchonComponents.Icons, only: [archon_icon: 1]
  import IchorWeb.Components.ArchonComponents.CommandHud, only: [command_hud: 1]
  import IchorWeb.Components.ArchonComponents.ChatPanel, only: [chat_panel: 1]
  import IchorWeb.Components.ArchonComponents.ReferencePanel, only: [reference_panel: 1]

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false
  attr :tab, :atom, default: :command
  attr :snapshot, :map, default: %{}
  attr :attention, :list, default: []
  attr :position, :atom, default: :center
  attr :size, :integer, default: 75
  attr :show_settings, :boolean, default: false

  def archon_overlay(assigns) do
    assigns =
      assigns
      |> assign(:shortcodes, CommandManifest.reference_commands())
      |> assign(:quick_actions, CommandManifest.quick_actions())
      |> assign(:positions, PanelHelpers.positions())
      |> assign(:sizes, PanelHelpers.sizes())

    ~H"""
    <div class="archon-overlay">
      <div class="archon-backdrop" phx-click="archon_close" />
      <div
        id="archon-panel"
        phx-hook="ArchonPanel"
        class="archon-panel"
        style={PanelHelpers.floating_style(@position, @size)}
      >
        <%!-- Red accent line --%>
        <div class="absolute top-0 left-0 right-0 h-0.5 bg-[hsl(355_84%_54%)] z-10" />

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
              <button
                phx-click="archon_set_tab"
                phx-value-tab="command"
                class={"archon-tab #{if @tab == :command, do: "archon-tab-active", else: ""}"}
              >
                <span class="archon-tab-key">Q</span> Command
              </button>
              <button
                phx-click="archon_set_tab"
                phx-value-tab="chat"
                class={"archon-tab #{if @tab == :chat, do: "archon-tab-active", else: ""}"}
              >
                <span class="archon-tab-key">W</span> Chat
              </button>
              <button
                phx-click="archon_set_tab"
                phx-value-tab="ref"
                class={"archon-tab #{if @tab == :ref, do: "archon-tab-active", else: ""}"}
              >
                <span class="archon-tab-key">E</span> Reference
              </button>
            </div>
            <%!-- Settings --%>
            <button
              phx-click="archon_toggle_settings"
              class={"archon-close-btn #{if @show_settings, do: "!text-[hsl(355_84%_54%)]", else: ""}"}
              title="Panel settings"
            >
              <svg
                class="w-3.5 h-3.5"
                viewBox="0 0 16 16"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
              >
                <circle cx="8" cy="8" r="2.5" />
                <path d="M8 1v2M8 13v2M1 8h2M13 8h2M2.9 2.9l1.4 1.4M11.7 11.7l1.4 1.4M2.9 13.1l1.4-1.4M11.7 4.3l1.4-1.4" />
              </svg>
            </button>
            <button phx-click="archon_close" class="archon-close-btn">
              <kbd class="archon-kbd">esc</kbd>
            </button>
          </div>
        </div>

        <%!-- Settings bar --%>
        <div
          :if={@show_settings}
          class="px-5 py-2.5 shrink-0 flex items-center gap-6"
          style="border-bottom: 1px solid hsl(var(--noir-border)); background: hsl(var(--noir-surface));"
        >
          <div>
            <div class="archon-section-title mb-1.5">Position</div>
            <div class="flex gap-1">
              <%= for pos <- @positions do %>
                <button
                  phx-click="archon_set_position"
                  phx-value-position={pos}
                  class={archon_setting_class(pos == @position)}
                >
                  {PanelHelpers.position_label(pos)}
                </button>
              <% end %>
            </div>
          </div>
          <div>
            <div class="archon-section-title mb-1.5">Size</div>
            <div class="flex gap-1">
              <%= for size <- @sizes do %>
                <button
                  phx-click="archon_set_size"
                  phx-value-size={size}
                  class={archon_setting_class(size == @size)}
                >
                  {size}%
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <%!-- Content area --%>
        <div class="archon-content">
          <.command_hud
            :if={@tab == :command}
            actions={@quick_actions}
            loading={@loading}
            messages={@messages}
            snapshot={@snapshot}
            attention={@attention}
          />
          <.chat_panel :if={@tab == :chat} messages={@messages} loading={@loading} />
          <.reference_panel :if={@tab == :ref} shortcodes={@shortcodes} />
        </div>
      </div>
    </div>
    """
  end

  defp archon_setting_class(true) do
    [
      "px-2.5 py-1 text-[0.625rem] font-mono uppercase tracking-wider cursor-pointer transition-all",
      "bg-[hsl(355_84%_54%/0.08)] text-[hsl(355_84%_54%)] border border-[hsl(355_84%_54%/0.25)]"
    ]
  end

  defp archon_setting_class(false) do
    [
      "px-2.5 py-1 text-[0.625rem] font-mono uppercase tracking-wider cursor-pointer transition-all",
      "bg-[hsl(var(--noir-surface))] text-[hsl(var(--noir-text-muted))] border border-[hsl(var(--noir-border))]",
      "hover:text-[hsl(var(--noir-text))]"
    ]
  end

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
