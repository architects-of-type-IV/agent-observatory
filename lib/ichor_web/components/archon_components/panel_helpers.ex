defmodule IchorWeb.Components.ArchonComponents.PanelHelpers do
  @moduledoc """
  Floating panel positioning for the Archon overlay.
  Same positioning model as the terminal panel -- always floating,
  positions: center, bottom, top, left, right.
  Respects app header clearance (6.5rem).
  """

  @header "6.5rem"
  @gap "1rem"

  @positions [:center, :bottom, :top, :left, :right]
  @sizes [50, 75, 100]

  @doc "Available position options."
  @spec positions :: [atom()]
  def positions, do: @positions

  @doc "Available size options."
  @spec sizes :: [integer()]
  def sizes, do: @sizes

  @doc "Compute inline CSS for Archon floating panel."
  @spec floating_style(atom(), integer()) :: String.t()
  def floating_style(:center, size) do
    {w, h} = dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + (100vh - #{@header} - #{h}vh) / 2);",
      "left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:bottom, size) do
    {w, h} = dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "bottom: #{@gap}; left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:top, size) do
    {w, h} = dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + #{@gap}); left: 50%; transform: translateX(-50%);",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:left, size) do
    {w, h} = dimensions(size)

    [
      "width: #{w}%; height: #{h}%;",
      "top: calc(#{@header} + (100vh - #{@header} - #{h}vh) / 2);",
      "left: #{@gap};",
      max_height()
    ]
    |> Enum.join(" ")
  end

  def floating_style(:right, size) do
    {w, h} = dimensions(size)

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

  defp dimensions(100), do: {98, 88}
  defp dimensions(size), do: {min(size + 15, 90), size}

  defp max_height, do: "max-height: calc(100vh - #{@header} - #{@gap});"
end
