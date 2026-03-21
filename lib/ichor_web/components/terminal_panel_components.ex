defmodule IchorWeb.Components.TerminalPanelComponents do
  @moduledoc """
  VS Code-style terminal panel overlay.

  Features: T-key toggle, position presets (bottom/top/left/right/floating),
  size presets (25%/33%/50%/75%/fullscreen), session tabs, drag resize handle.
  """

  use Phoenix.Component

  @doc """
  Renders the terminal panel overlay.

  ## Assigns

    * `:panel_visible` - whether the panel is shown
    * `:panel_position` - :bottom | :top | :left | :right | :floating
    * `:panel_size` - integer percentage (25, 33, 50, 75, 100)
    * `:tmux_panels` - list of open session names
    * `:active_tmux_session` - currently active session name
    * `:tmux_sessions` - all available tmux sessions for the session picker
  """
  attr :panel_visible, :boolean, required: true
  attr :panel_position, :atom, required: true
  attr :panel_size, :integer, required: true
  attr :tmux_panels, :list, required: true
  attr :active_tmux_session, :string, default: nil
  attr :tmux_sessions, :list, required: true
  attr :show_session_picker, :boolean, default: false

  def terminal_panel(assigns) do
    ~H"""
    <%!-- Hidden indicator when panel is hidden --%>
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

    <%!-- Terminal panel --%>
    <div
      id="terminal-panel"
      phx-hook="TerminalPanel"
      class={[
        "fixed z-40 flex flex-col bg-[#0f0f14] border border-border overflow-hidden",
        "transition-all duration-300 ease-[cubic-bezier(0.4,0,0.2,1)]",
        panel_position_classes(@panel_position),
        panel_size_style(@panel_position, @panel_size),
        if(!@panel_visible, do: panel_hidden_class(@panel_position), else: "")
      ]}
      style={panel_inline_style(@panel_position, @panel_size, @panel_visible)}
    >
      <%!-- Resize handle --%>
      <div
        :if={@panel_position not in [:floating]}
        class={[
          "shrink-0 flex items-center justify-center",
          "bg-[oklch(22%_0.01_254)] hover:bg-[color-mix(in_oklch,oklch(58%_0.233_277.117)_30%,oklch(22%_0.01_254))]",
          "text-[oklch(35%_0.01_254)] hover:text-[oklch(58%_0.233_277.117)]",
          "transition-colors duration-150",
          resize_handle_classes(@panel_position)
        ]}
        style="z-index: 1;"
      >
        <svg :if={@panel_position in [:bottom, :top]} class="w-8 h-1.5 opacity-60" viewBox="0 0 32 6">
          <line
            x1="8"
            y1="2"
            x2="24"
            y2="2"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
          />
          <line
            x1="8"
            y1="5"
            x2="24"
            y2="5"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
          />
        </svg>
        <svg :if={@panel_position in [:left, :right]} class="w-1.5 h-8 opacity-60" viewBox="0 0 6 32">
          <line
            x1="2"
            y1="8"
            x2="2"
            y2="24"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
          />
          <line
            x1="5"
            y1="8"
            x2="5"
            y2="24"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
          />
        </svg>
      </div>

      <%!-- Panel header --%>
      <header class="flex items-center h-8 bg-[oklch(18%_0.012_254)] border-b border-[oklch(28%_0.012_254)] shrink-0 select-none">
        <%!-- Drag handle --%>
        <div class="w-8 h-full flex items-center justify-center cursor-grab active:cursor-grabbing text-[oklch(40%_0.01_254)] shrink-0">
          <svg class="w-3.5 h-3.5" viewBox="0 0 16 16" fill="currentColor">
            <circle cx="5" cy="4" r="1" /><circle cx="11" cy="4" r="1" />
            <circle cx="5" cy="8" r="1" /><circle cx="11" cy="8" r="1" />
            <circle cx="5" cy="12" r="1" /><circle cx="11" cy="12" r="1" />
          </svg>
        </div>

        <%!-- Session tabs --%>
        <nav class="flex items-stretch flex-1 overflow-hidden h-full" aria-label="Terminal sessions">
          <%= for session <- @tmux_panels do %>
            <% is_active = session == @active_tmux_session %>
            <button
              phx-click="switch_tmux_tab"
              phx-value-session={session}
              class={[
                "flex items-center gap-1.5 px-3 text-[11px] font-mono whitespace-nowrap",
                "border-r border-[oklch(22%_0.01_254)] cursor-pointer transition-colors h-full relative",
                if(is_active,
                  do: "bg-[#0f0f14] text-[oklch(95%_0.01_256)]",
                  else:
                    "text-[oklch(55%_0.01_254)] hover:bg-[oklch(22%_0.01_254)] hover:text-[oklch(95%_0.01_256)]"
                )
              ]}
            >
              <span class={[
                "w-1.5 h-1.5 rounded-full shrink-0",
                if(is_active, do: "bg-success", else: "bg-highlight")
              ]} />
              <span>{session}</span>
              <span
                phx-click="disconnect_tmux_tab"
                phx-value-session={session}
                class="w-3.5 h-3.5 flex items-center justify-center rounded text-[10px] text-[oklch(45%_0.01_254)] hover:bg-error hover:text-white transition-colors"
              >
                x
              </span>
              <span :if={is_active} class="absolute bottom-0 left-0 right-0 h-0.5 bg-brand" />
            </button>
          <% end %>

          <%!-- Add session button with dropdown --%>
          <div class="relative shrink-0" id="term-session-picker">
            <button
              phx-click="toggle_session_picker"
              class="w-8 h-full flex items-center justify-center text-[oklch(45%_0.01_254)] cursor-pointer border-r border-[oklch(22%_0.01_254)] hover:bg-[oklch(22%_0.01_254)] hover:text-[oklch(95%_0.01_256)] transition-colors text-sm"
              title="Add session"
            >
              +
            </button>
          </div>
        </nav>

        <%!-- Panel controls --%>
        <div
          class="flex items-center gap-0 px-1.5 shrink-0"
          role="toolbar"
          aria-label="Panel controls"
        >
          <%!-- Position cycle --%>
          <button
            phx-click="cycle_panel_position"
            class="w-7 h-7 flex items-center justify-center rounded text-[oklch(45%_0.01_254)] hover:bg-[oklch(22%_0.01_254)] hover:text-[oklch(95%_0.01_256)] transition-colors text-[10px] font-mono"
            title={"Position: #{@panel_position}"}
          >
            {position_icon(@panel_position)}
          </button>
          <%!-- Size cycle --%>
          <button
            phx-click="cycle_panel_size"
            class="w-7 h-7 flex items-center justify-center rounded text-[oklch(45%_0.01_254)] hover:bg-[oklch(22%_0.01_254)] hover:text-[oklch(95%_0.01_256)] transition-colors text-[10px] font-mono"
            title={"Size: #{@panel_size}%"}
          >
            {@panel_size}%
          </button>
          <%!-- Minimize --%>
          <button
            phx-click="toggle_terminal_panel"
            class="w-7 h-7 flex items-center justify-center rounded text-[oklch(45%_0.01_254)] hover:bg-[oklch(22%_0.01_254)] hover:text-[oklch(95%_0.01_256)] transition-colors"
            title="Hide panel (T to restore)"
          >
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
          <%!-- Close --%>
          <button
            phx-click="close_terminal_panel"
            class="w-7 h-7 flex items-center justify-center rounded text-[oklch(45%_0.01_254)] hover:bg-error hover:text-white transition-colors"
            title="Close panel"
          >
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

      <%!-- Terminal body: xterm pane --%>
      <div class="flex-1 overflow-hidden min-h-0">
        <div
          :if={@active_tmux_session}
          id={"xterm-panel-#{@active_tmux_session}"}
          phx-hook="XtermTerminal"
          phx-update="ignore"
          data-session={@active_tmux_session}
          class="w-full h-full"
          style="background: #0f0f14;"
        />
        <div
          :if={@active_tmux_session == nil}
          class="flex items-center justify-center h-full text-[oklch(45%_0.01_254)] text-xs"
        >
          <div class="text-center">
            <p class="mb-2">No terminal session open</p>
            <p class="text-[10px]">Click + to add a tmux session</p>
          </div>
        </div>
      </div>

      <%!-- Input bar --%>
      <div
        :if={@active_tmux_session}
        class="px-3 py-1.5 border-t border-[oklch(22%_0.01_254)] bg-[oklch(16%_0.01_254)] shrink-0"
      >
        <div class="flex items-center gap-2">
          <span class="text-[10px] text-brand font-mono shrink-0">
            {@active_tmux_session} &gt;
          </span>
          <div id="term-panel-input-stable" phx-update="ignore" class="flex-1">
            <form phx-submit="send_tmux_keys" class="flex gap-2">
              <input
                type="text"
                name="keys"
                placeholder="Send keys..."
                autocomplete="off"
                class="flex-1 bg-[oklch(20%_0.012_254)] border border-[oklch(28%_0.012_254)] rounded px-2 py-1 text-[11px] font-mono text-[oklch(95%_0.01_256)] placeholder-[oklch(40%_0.01_254)] focus:border-brand focus:outline-none"
              />
              <button
                type="submit"
                class="px-2.5 py-1 bg-brand/20 text-brand text-[10px] font-medium rounded border border-brand/30 hover:bg-brand/30 transition-colors"
              >
                Send
              </button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Session picker dropdown --%>
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

  # Position CSS classes (using fixed positioning)
  defp panel_position_classes(:bottom), do: "bottom-0 left-0 right-0 rounded-t-lg border-b-0"
  defp panel_position_classes(:top), do: "top-0 left-0 right-0 rounded-b-lg border-t-0"
  defp panel_position_classes(:left), do: "left-0 top-0 bottom-0 rounded-r-lg border-l-0"
  defp panel_position_classes(:right), do: "right-0 top-0 bottom-0 rounded-l-lg border-r-0"
  defp panel_position_classes(:floating), do: "rounded-lg shadow-2xl"
  defp panel_position_classes(_), do: panel_position_classes(:bottom)

  # Inline styles for size (can't do dynamic % with Tailwind)
  defp panel_inline_style(:floating, size, visible) do
    w = min(size * 1.2, 90)

    base =
      "width: #{w}%; height: #{size}%; top: 50%; left: 50%; transform: translate(-50%, -50%);"

    if visible, do: base, else: base <> " opacity: 0; pointer-events: none;"
  end

  defp panel_inline_style(pos, size, _visible) when pos in [:left, :right] do
    "width: #{size}%;"
  end

  defp panel_inline_style(_pos, size, _visible) do
    "height: #{size}%;"
  end

  # Hidden animation classes
  defp panel_hidden_class(:bottom), do: "translate-y-full"
  defp panel_hidden_class(:top), do: "-translate-y-full"
  defp panel_hidden_class(:left), do: "-translate-x-full"
  defp panel_hidden_class(:right), do: "translate-x-full"
  defp panel_hidden_class(:floating), do: "opacity-0 scale-95 pointer-events-none"
  defp panel_hidden_class(_), do: panel_hidden_class(:bottom)

  # Resize handle classes per position
  defp resize_handle_classes(:bottom), do: "resize-handle h-1 w-full cursor-row-resize"
  defp resize_handle_classes(:top), do: "resize-handle h-1 w-full cursor-row-resize order-last"
  defp resize_handle_classes(:left), do: "resize-handle w-1 h-full cursor-col-resize order-last"
  defp resize_handle_classes(:right), do: "resize-handle w-1 h-full cursor-col-resize"
  defp resize_handle_classes(_), do: resize_handle_classes(:bottom)

  # Panel size style (computed as Tailwind can't do dynamic %)
  defp panel_size_style(_position, _size), do: ""

  # Position icons for the cycle button
  defp position_icon(:bottom), do: "B"
  defp position_icon(:top), do: "T"
  defp position_icon(:left), do: "L"
  defp position_icon(:right), do: "R"
  defp position_icon(:floating), do: "F"
  defp position_icon(_), do: "B"
end
