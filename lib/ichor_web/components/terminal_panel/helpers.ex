defmodule IchorWeb.Components.TerminalPanel.Helpers do
  @moduledoc """
  Positioning, theming, and label helpers for the terminal panel.

  All floating positions respect the app header clearance (5.5rem)
  so the panel never overlaps navigation.
  """

  # Header height + gap for panel positioning
  @header "6.5rem"
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

  @doc "Compute inline CSS for floating panel position and size."
  @spec floating_style(atom(), integer()) :: String.t()
  def floating_style(:center, size) do
    {w, h} = float_dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + (100vh - #{@header} - #{h}vh) / 2);",
      "left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:bottom, size) do
    {w, h} = float_dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "bottom: #{@gap}; left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:top, size) do
    {w, h} = float_dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + #{@gap}); left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:left, size) do
    {w, h} = float_dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + (100vh - #{@header} - #{h}vh) / 2);",
      "left: #{@gap};",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:right, size) do
    {w, h} = float_dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + (100vh - #{@header} - #{h}vh) / 2);",
      "right: #{@gap}; left: auto;",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(_, size), do: floating_style(:center, size)

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

  defp float_dimensions(100), do: {96, 90}
  defp float_dimensions(size), do: {min(size + 20, 90), size}

  defp max_height, do: "max-height: calc(100vh - #{@header} - #{@gap});"
end
