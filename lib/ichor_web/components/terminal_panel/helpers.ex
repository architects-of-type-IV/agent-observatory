defmodule IchorWeb.Components.TerminalPanel.Helpers do
  @moduledoc """
  Positioning, theming, and label helpers for the terminal panel.

  All floating positions respect the app header clearance (6.5rem)
  so the panel never overlaps navigation. Width and height are independent.
  """

  # Dynamic: JS measures actual header and sets --app-header-h on :root
  @header "var(--app-header-h, 7.5rem)"
  @gap "1rem"

  @spec split_sessions(list(), String.t() | nil, atom()) :: list()
  def split_sessions(panels, active, :none), do: [active || List.first(panels)]

  def split_sessions(panels, active, _split) do
    case panels do
      [] ->
        []

      [single] ->
        [single]

      _ ->
        active_idx = Enum.find_index(panels, &(&1 == active)) || 0
        Enum.slice(panels, active_idx, min(2, length(panels) - active_idx))
    end
  end

  @doc "Compute inline CSS for floating panel with independent width and height."
  @spec floating_style(atom(), integer(), integer()) :: String.t()
  def floating_style(:bottom, w, h) do
    "width: min(#{w}%, 100% - 2 * #{@gap}); height: #{h}%; bottom: #{@gap}; left: 50%; transform: translateX(-50%); #{mh()}"
  end

  def floating_style(pos, w, h) when pos in [:center, :top, :left, :right] do
    horiz =
      case pos do
        :right -> "right: #{@gap}; left: auto;"
        :left -> "left: #{@gap};"
        _ -> "left: 50%; transform: translateX(-50%);"
      end

    "width: min(#{w}%, 100% - 2 * #{@gap}); height: #{h}%; top: calc(#{@header} + #{@gap}); bottom: #{@gap}; #{horiz} #{mh()}"
  end

  def floating_style(_, w, h), do: floating_style(:center, w, h)

  @doc "Human-readable position label."
  @spec position_label(atom()) :: String.t()
  def position_label(:center), do: "Center"
  def position_label(:bottom), do: "Bottom"
  def position_label(:top), do: "Top"
  def position_label(:left), do: "Left"
  def position_label(:right), do: "Right"
  def position_label(_), do: "Center"

  @doc "Human-readable split mode label."
  @spec split_label(atom()) :: String.t()
  def split_label(:none), do: "None"
  def split_label(:horizontal), do: "Horiz"
  def split_label(:vertical), do: "Vert"
  def split_label(_), do: "None"

  @doc "Human-readable theme label."
  @spec theme_label(atom()) :: String.t()
  def theme_label(:ichor), do: "ICHOR"
  def theme_label(:midnight), do: "Midnight"
  def theme_label(:aurora), do: "Aurora"
  def theme_label(:phosphor), do: "Phosphor"
  def theme_label(:solarized), do: "Solarized"
  def theme_label(:rose), do: "Rose"
  def theme_label(_), do: "ICHOR"

  defp mh, do: "max-height: calc(100vh - #{@header} - #{@gap});"
end
