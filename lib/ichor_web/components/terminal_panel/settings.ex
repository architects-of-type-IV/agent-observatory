defmodule IchorWeb.Components.TerminalPanel.Settings do
  @moduledoc """
  Settings bar for the terminal panel.
  Renders position, size, split, and theme option groups.
  """

  use Phoenix.Component

  import IchorWeb.Components.TerminalPanel.Helpers,
    only: [position_label: 1, split_label: 1, theme_label: 1]

  @positions [:center, :bottom, :top, :left, :right]
  @sizes [25, 33, 50, 75, 100]
  @splits [:none, :horizontal, :vertical]
  @themes [:ichor, :midnight, :aurora, :phosphor, :solarized, :rose]

  attr :panel_position, :atom, required: true
  attr :panel_size, :integer, required: true
  attr :panel_split, :atom, required: true
  attr :panel_theme, :atom, required: true

  def settings_bar(assigns) do
    assigns =
      assigns
      |> assign(:positions, @positions)
      |> assign(:sizes, @sizes)
      |> assign(:splits, @splits)
      |> assign(:themes, @themes)

    ~H"""
    <div class="bg-[var(--term-surface)] border-b border-[var(--term-border)] px-3 py-2.5 shrink-0">
      <div class="grid grid-cols-4 gap-x-4 gap-y-2.5">
        <.setting_group label="Position">
          <.setting_btn
            :for={pos <- @positions}
            event="set_panel_position"
            value={pos}
            label={position_label(pos)}
            active={pos == @panel_position}
          />
        </.setting_group>
        <.setting_group label="Size">
          <.setting_btn
            :for={size <- @sizes}
            event="set_panel_size"
            value={size}
            label={"#{size}%"}
            active={size == @panel_size}
          />
        </.setting_group>
        <.setting_group label="Split">
          <.setting_btn
            :for={split <- @splits}
            event="set_panel_split"
            value={split}
            label={split_label(split)}
            active={split == @panel_split}
          />
        </.setting_group>
        <.setting_group label="Theme">
          <.setting_btn
            :for={theme <- @themes}
            event="set_panel_theme"
            value={theme}
            label={theme_label(theme)}
            active={theme == @panel_theme}
          />
        </.setting_group>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp setting_group(assigns) do
    ~H"""
    <div>
      <div class="text-[9px] text-[var(--term-text-muted)] uppercase tracking-wider font-semibold mb-1.5">
        {@label}
      </div>
      <div class="flex gap-1 flex-wrap">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :active, :boolean, required: true

  defp setting_btn(assigns) do
    ~H"""
    <button
      phx-click={@event}
      phx-value-position={if @event == "set_panel_position", do: @value}
      phx-value-size={if @event == "set_panel_size", do: @value}
      phx-value-split={if @event == "set_panel_split", do: @value}
      phx-value-theme={if @event == "set_panel_theme", do: @value}
      class={["term-setting", if(@active, do: "active")]}
    >
      {@label}
    </button>
    """
  end
end
