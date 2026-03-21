defmodule IchorWeb.Components.TerminalPanel.Settings do
  @moduledoc """
  Settings panel for the terminal panel.
  Visual 3x3 grid for position+size, plus split and theme controls.
  """

  use Phoenix.Component

  import IchorWeb.Components.TerminalPanel.Helpers,
    only: [split_label: 1, theme_label: 1]

  @splits [:none, :horizontal, :vertical]
  @themes [:ichor, :midnight, :aurora, :phosphor, :solarized, :rose]

  # 3x3 grid: each cell maps to {position, width, height}
  @grid [
    # top row
    %{pos: :left, w: 33, h: 33, label: "TL", row: 0, col: 0},
    %{pos: :top, w: 100, h: 33, label: "Top", row: 0, col: 1},
    %{pos: :right, w: 33, h: 33, label: "TR", row: 0, col: 2},
    # middle row
    %{pos: :left, w: 33, h: 100, label: "Left", row: 1, col: 0},
    %{pos: :center, w: 70, h: 50, label: "Center", row: 1, col: 1},
    %{pos: :right, w: 33, h: 100, label: "Right", row: 1, col: 2},
    # bottom row
    %{pos: :left, w: 33, h: 33, label: "BL", row: 2, col: 0},
    %{pos: :bottom, w: 100, h: 33, label: "Bottom", row: 2, col: 1},
    %{pos: :right, w: 33, h: 33, label: "BR", row: 2, col: 2}
  ]

  attr :panel_position, :atom, required: true
  attr :panel_width, :integer, required: true
  attr :panel_height, :integer, required: true
  attr :panel_split, :atom, required: true
  attr :panel_theme, :atom, required: true

  def settings_bar(assigns) do
    assigns =
      assigns
      |> assign(:grid, @grid)
      |> assign(:splits, @splits)
      |> assign(:themes, @themes)

    ~H"""
    <div class="bg-[var(--term-surface)] border-b border-[var(--term-border)] px-3 py-2.5 shrink-0">
      <div class="flex gap-x-5 gap-y-2.5 items-start flex-wrap">
        <%!-- Visual grid --%>
        <div>
          <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
            Layout
          </div>
          <div class="grid grid-cols-3 gap-px w-[7.5rem]" style="background: var(--term-border);">
            <%= for cell <- @grid do %>
              <% active = grid_active?(cell, @panel_position, @panel_width, @panel_height) %>
              <button
                phx-click="set_panel_layout"
                phx-value-pos={cell.pos}
                phx-value-w={cell.w}
                phx-value-h={cell.h}
                class={[
                  "h-6 flex items-center justify-center text-[8px] font-mono transition-colors cursor-pointer",
                  if(active,
                    do: "bg-brand/25 text-brand",
                    else:
                      "bg-[var(--term-surface)] text-[var(--term-text-dim)] hover:bg-[var(--term-hover)] hover:text-[var(--term-text)]"
                  )
                ]}
                title={"#{cell.label}: #{cell.w}% x #{cell.h}%"}
              >
                {cell.label}
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Fine-tune width/height --%>
        <div>
          <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
            Width
          </div>
          <div class="flex gap-1">
            <.setting_btn
              :for={d <- [25, 33, 50, 75, 100]}
              event="set_panel_width"
              value={d}
              label={"#{d}%"}
              active={d == @panel_width}
            />
          </div>
        </div>
        <div>
          <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
            Height
          </div>
          <div class="flex gap-1">
            <.setting_btn
              :for={d <- [25, 33, 50, 75, 100]}
              event="set_panel_height"
              value={d}
              label={"#{d}%"}
              active={d == @panel_height}
            />
          </div>
        </div>

        <%!-- Split --%>
        <div>
          <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
            Split
          </div>
          <div class="flex gap-1">
            <.setting_btn
              :for={split <- @splits}
              event="set_panel_split"
              value={split}
              label={split_label(split)}
              active={split == @panel_split}
            />
          </div>
        </div>

        <%!-- Theme --%>
        <div>
          <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
            Theme
          </div>
          <div class="flex gap-1">
            <.setting_btn
              :for={theme <- @themes}
              event="set_panel_theme"
              value={theme}
              label={theme_label(theme)}
              active={theme == @panel_theme}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp grid_active?(%{pos: pos, w: w, h: h}, panel_pos, panel_w, panel_h) do
    pos == panel_pos and w == panel_w and h == panel_h
  end

  attr :event, :string, required: true
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp setting_btn(assigns) do
    ~H"""
    <button
      phx-click={@event}
      phx-value-val={@value}
      class={["term-setting", if(@active, do: "active")]}
    >
      {@label}
    </button>
    """
  end
end
