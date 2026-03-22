defmodule IchorWeb.Components.TerminalPanelComponents do
  @moduledoc """
  VS Code-style floating terminal panel overlay.

  Always floating. Positions: center, left, right, bottom, top.
  Sizes: 25%, 33%, 50%, 75%, full. Split: none, horizontal, vertical.
  6 terminal themes. T-key toggle. Session tabs.

  Sub-components live in `terminal_panel/`:
  - `SessionTab` -- individual tab in the header
  - `Settings` -- settings bar with position/size/split/theme pickers
  - `Helpers` -- positioning, theme, and label functions
  """

  use Phoenix.Component

  import IchorWeb.Components.TerminalPanel.Helpers,
    only: [floating_style: 3, split_sessions: 3]

  import IchorWeb.Components.TerminalPanel.SessionTab, only: [session_tab: 1]

  alias Phoenix.LiveView.JS
  alias IchorWeb.Components.TerminalPanel.Settings

  attr :panel_visible, :boolean, required: true
  attr :panel_position, :atom, required: true
  attr :panel_width, :integer, required: true
  attr :panel_height, :integer, required: true
  attr :panel_split, :atom, required: true
  attr :panel_theme, :atom, required: true
  attr :tmux_panels, :list, required: true
  attr :active_tmux_session, :string, default: nil
  attr :tmux_sessions, :list, required: true
  attr :show_session_picker, :boolean, default: false
  attr :show_panel_settings, :boolean, default: false

  def terminal_panel(assigns) do
    assigns =
      assign(
        assigns,
        :split_sessions,
        split_sessions(assigns.tmux_panels, assigns.active_tmux_session, assigns.panel_split)
      )

    ~H"""
    <%!-- Hidden indicator --%>
    <div
      :if={!@panel_visible && @tmux_panels != []}
      class="fixed bottom-3 left-1/2 -translate-x-1/2 z-40 bg-base/90 border border-border rounded-lg px-3 py-1.5 text-[11px] text-muted pointer-events-none backdrop-blur-sm"
    >
      Terminal hidden -- press
      <kbd class="inline-block bg-raised border border-border rounded px-1.5 py-0.5 text-[10px] font-mono text-default mx-0.5">
        T
      </kbd>
      to show
    </div>

    <%!-- Floating terminal panel --%>
    <div
      id="terminal-panel"
      phx-hook="TerminalPanel"
      data-theme={if @panel_theme != :ichor, do: @panel_theme}
      class={[
        "fixed z-40 flex flex-col border border-border overflow-hidden rounded-lg",
        "transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]",
        "shadow-[0_12px_48px_oklch(0%_0_0/0.6),0_2px_8px_oklch(0%_0_0/0.4)]",
        if(!@panel_visible, do: "opacity-0 scale-95 pointer-events-none", else: "")
      ]}
      style={floating_style(@panel_position, @panel_width, @panel_height)}
    >
      <%!-- Header --%>
      <header class="flex items-center h-8 bg-[var(--term-header)] border-b border-[var(--term-border-accent)] shrink-0 select-none">
        <div class="w-8 h-full flex items-center justify-center cursor-grab active:cursor-grabbing text-[var(--term-text-faint)] shrink-0">
          <svg class="w-3.5 h-3.5" viewBox="0 0 16 16" fill="currentColor">
            <circle cx="5" cy="4" r="1" /><circle cx="11" cy="4" r="1" />
            <circle cx="5" cy="8" r="1" /><circle cx="11" cy="8" r="1" />
            <circle cx="5" cy="12" r="1" /><circle cx="11" cy="12" r="1" />
          </svg>
        </div>

        <nav class="flex items-stretch flex-1 overflow-hidden h-full">
          <.session_tab
            :for={session <- @tmux_panels}
            session={session}
            active={session == @active_tmux_session}
          />
          <div class="relative shrink-0">
            <button
              phx-click="toggle_session_picker"
              class="term-tab"
              title="Add session"
              style="width: 2rem; padding: 0; justify-content: center; font-size: 0.875rem;"
            >
              +
            </button>
          </div>
        </nav>

        <%!-- Presets --%>
        <div class="flex items-center gap-0 border-l border-[var(--term-border)] px-0.5 shrink-0">
          <.preset_btn label="Side" pos="left" w="33" h="100" />
          <.preset_btn label="Bar" pos="bottom" w="100" h="33" />
          <.preset_btn label="Med" pos="center" w="70" h="50" />
          <.preset_btn label="Full" pos="center" w="100" h="100" />
        </div>

        <div class="flex items-center gap-0 px-1.5 shrink-0">
          <button
            phx-click="toggle_panel_settings"
            class={["term-ctrl", if(@show_panel_settings, do: "active")]}
            title="Settings"
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
          <button phx-click="toggle_terminal_panel" class="term-ctrl" title="Hide (T to restore)">
            <svg
              class="w-3 h-3"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <line x1="3" y1="8" x2="13" y2="8" />
            </svg>
          </button>
          <button phx-click="close_terminal_panel" class="term-ctrl close" title="Close panel">
            <svg
              class="w-3 h-3"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
            >
              <line x1="4" y1="4" x2="12" y2="12" /><line x1="12" y1="4" x2="4" y2="12" />
            </svg>
          </button>
        </div>
      </header>

      <%!-- Settings --%>
      <Settings.settings_bar
        :if={@show_panel_settings}
        panel_position={@panel_position}
        panel_width={@panel_width}
        panel_height={@panel_height}
        panel_split={@panel_split}
        panel_theme={@panel_theme}
      />

      <%!-- Terminal body --%>
      <div class="flex-1 overflow-hidden min-h-0 bg-[var(--term-bg)]">
        <%= if @panel_split == :none do %>
          <div
            :if={@active_tmux_session}
            id={"xterm-panel-#{@active_tmux_session}"}
            phx-hook="XtermTerminal"
            phx-update="ignore"
            data-session={@active_tmux_session}
            class="w-full h-full"
            style="background: var(--term-bg);"
          />
          <.empty_state :if={@active_tmux_session == nil} />
        <% else %>
          <div class={[
            "w-full h-full flex",
            if(@panel_split == :horizontal, do: "flex-row", else: "flex-col")
          ]}>
            <%= for {session, idx} <- Enum.with_index(@split_sessions) do %>
              <div
                :if={idx > 0}
                class={[
                  "shrink-0 bg-[var(--term-border)] hover:bg-brand/60 transition-colors",
                  if(@panel_split == :horizontal,
                    do: "w-[3px] cursor-col-resize",
                    else: "h-[3px] cursor-row-resize"
                  )
                ]}
              />
              <div class="flex-1 flex flex-col min-w-0 min-h-0 overflow-hidden">
                <div class="flex items-center px-2 h-5 bg-[var(--term-surface)] border-b border-[var(--term-border)] shrink-0 gap-1.5">
                  <span class={[
                    "w-1.5 h-1.5 rounded-full shrink-0",
                    if(session == @active_tmux_session, do: "bg-success", else: "bg-highlight")
                  ]} />
                  <span
                    phx-click="switch_tmux_tab"
                    phx-value-session={session}
                    class="text-[10px] font-mono text-[var(--term-text-muted)] cursor-pointer hover:text-[var(--term-active)]"
                  >
                    {session}
                  </span>
                </div>
                <div
                  :if={session}
                  id={"xterm-split-#{session}"}
                  phx-hook="XtermTerminal"
                  phx-update="ignore"
                  data-session={session}
                  class="flex-1 min-h-0"
                  style="background: var(--term-bg);"
                />
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <%!-- Input bar --%>
      <div
        :if={@active_tmux_session}
        class="px-3 py-1.5 border-t border-[var(--term-border)] bg-[var(--term-surface)] shrink-0"
      >
        <div class="flex items-center gap-2">
          <span class="text-[10px] text-brand font-mono shrink-0">
            {@active_tmux_session} &gt;
          </span>
          <div id="term-panel-input-stable" phx-update="ignore" class="flex-1">
            <form
              id="term-keys-form"
              phx-submit={JS.push("send_tmux_keys") |> JS.dispatch("reset", to: "#term-keys-form")}
              class="flex gap-2"
            >
              <input
                type="text"
                name="keys"
                placeholder="Send keys..."
                autocomplete="off"
                class="flex-1 term-input"
              />
              <button type="submit" class="ichor-btn ichor-btn-primary text-[10px]">Send</button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Session picker --%>
      <div
        :if={@show_session_picker}
        id="session-picker-dropdown"
        class="absolute top-8 left-8 z-50 bg-base border border-border rounded-lg shadow-xl py-1 min-w-[200px] max-h-[300px] overflow-y-auto"
        phx-click-away="toggle_session_picker"
      >
        <div class="px-3 py-1.5 text-[10px] text-muted font-semibold uppercase tracking-wider border-b border-border">
          Available Sessions
        </div>
        <%= for session <- @tmux_sessions do %>
          <% already_open = session in @tmux_panels %>
          <button
            phx-click={unless already_open, do: "connect_tmux"}
            phx-value-session={session}
            class={[
              "w-full text-left px-3 py-1.5 text-[11px] font-mono flex items-center gap-2 transition-colors",
              if(already_open,
                do: "text-muted cursor-default",
                else: "text-default hover:bg-raised cursor-pointer"
              )
            ]}
            disabled={already_open}
          >
            <span class={[
              "w-1.5 h-1.5 rounded-full shrink-0",
              if(already_open, do: "bg-success", else: "bg-highlight")
            ]} />
            {session}
            <span :if={already_open} class="ml-auto text-[9px] text-muted">open</span>
          </button>
        <% end %>
        <div :if={@tmux_sessions == []} class="px-3 py-2 text-[11px] text-muted italic">
          No tmux sessions found
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :pos, :string, required: true
  attr :w, :string, required: true
  attr :h, :string, required: true

  defp preset_btn(assigns) do
    ~H"""
    <button
      phx-click="set_panel_layout"
      phx-value-pos={@pos}
      phx-value-w={@w}
      phx-value-h={@h}
      class="term-ctrl text-[9px] font-mono !w-auto px-1.5"
      title={"#{@label}: #{@pos} #{@w}% x #{@h}%"}
    >
      {@label}
    </button>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex items-center justify-center h-full text-[var(--term-text-dim)] text-xs">
      <div class="text-center">
        <p class="mb-2">No terminal session open</p>
        <p class="text-[10px]">Click + to add a tmux session</p>
      </div>
    </div>
    """
  end
end
