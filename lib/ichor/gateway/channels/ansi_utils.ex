defmodule Ichor.Gateway.Channels.AnsiUtils do
  @moduledoc """
  ANSI escape sequence utilities.

  Provides two rendering modes:
  - `strip_ansi/1` -- removes all ANSI codes (plain text output)
  - `to_html/1` -- converts ANSI SGR codes to HTML spans (safe HTML output)
  """

  @ansi_escape ~r/\e\[([0-9;]*)([A-Za-z])/

  @doc "Strip ANSI escape sequences from a string."
  @spec strip_ansi(String.t()) :: String.t()
  def strip_ansi(text) do
    Regex.replace(@ansi_escape, text, "")
  end

  @doc """
  Convert ANSI SGR escape sequences to HTML spans with inline styles.
  Returns a Phoenix-safe HTML string suitable for `raw/1` in HEEx.
  Output is HTML-escaped except for the generated span tags.
  """
  @spec to_html(String.t()) :: String.t()
  def to_html(text) do
    {html, open_spans} =
      Regex.split(@ansi_escape, text, include_captures: true, trim: false)
      |> Enum.reduce({"", 0}, fn chunk, {acc, spans} ->
        case Regex.run(@ansi_escape, chunk) do
          [_, params, "m"] -> render_sgr(acc, spans, params)
          [_, _, _] -> {acc, spans}
          nil -> {acc <> html_escape(chunk), spans}
        end
      end)

    close_tags = String.duplicate("</span>", open_spans)
    html <> close_tags
  end

  # SGR (Select Graphic Rendition) -- code "m"

  defp render_sgr(acc, spans, ""), do: close_all(acc, spans)
  defp render_sgr(acc, spans, "0"), do: close_all(acc, spans)

  defp render_sgr(acc, spans, params) do
    codes = params |> String.split(";") |> Enum.map(&parse_int/1)
    {style, extra_spans} = codes_to_style(codes)

    if style == "" do
      {acc, spans}
    else
      {acc <> ~s(<span style="#{style}">), spans + extra_spans}
    end
  end

  defp close_all(acc, 0), do: {acc, 0}
  defp close_all(acc, spans), do: {acc <> String.duplicate("</span>", spans), 0}

  # Maps a list of SGR codes to a CSS style string.
  # Returns {style_string, span_count} where span_count is always 1 when non-empty.
  defp codes_to_style(codes) do
    styles =
      codes
      |> Enum.flat_map(&code_to_css/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(";")

    if styles == "", do: {"", 0}, else: {styles, 1}
  end

  # SGR code -> list of CSS property strings

  # Reset (handled in render_sgr, but guard here too)
  defp code_to_css(0), do: []

  # Text attributes
  defp code_to_css(1), do: ["font-weight:bold"]
  defp code_to_css(2), do: ["opacity:0.6"]
  defp code_to_css(3), do: ["font-style:italic"]
  defp code_to_css(4), do: ["text-decoration:underline"]
  defp code_to_css(9), do: ["text-decoration:line-through"]

  # Standard foreground colors (30-37)
  defp code_to_css(30), do: ["color:var(--ansi-black,#1e1e1e)"]
  defp code_to_css(31), do: ["color:var(--ansi-red,#cd3131)"]
  defp code_to_css(32), do: ["color:var(--ansi-green,#0dbc79)"]
  defp code_to_css(33), do: ["color:var(--ansi-yellow,#e5e510)"]
  defp code_to_css(34), do: ["color:var(--ansi-blue,#2472c8)"]
  defp code_to_css(35), do: ["color:var(--ansi-magenta,#bc3fbc)"]
  defp code_to_css(36), do: ["color:var(--ansi-cyan,#11a8cd)"]
  defp code_to_css(37), do: ["color:var(--ansi-white,#e5e5e5)"]

  # Standard background colors (40-47)
  defp code_to_css(40), do: ["background:var(--ansi-black,#1e1e1e)"]
  defp code_to_css(41), do: ["background:var(--ansi-red,#cd3131)"]
  defp code_to_css(42), do: ["background:var(--ansi-green,#0dbc79)"]
  defp code_to_css(43), do: ["background:var(--ansi-yellow,#e5e510)"]
  defp code_to_css(44), do: ["background:var(--ansi-blue,#2472c8)"]
  defp code_to_css(45), do: ["background:var(--ansi-magenta,#bc3fbc)"]
  defp code_to_css(46), do: ["background:var(--ansi-cyan,#11a8cd)"]
  defp code_to_css(47), do: ["background:var(--ansi-white,#e5e5e5)"]

  # Bright foreground colors (90-97)
  defp code_to_css(90), do: ["color:var(--ansi-bright-black,#666666)"]
  defp code_to_css(91), do: ["color:var(--ansi-bright-red,#f14c4c)"]
  defp code_to_css(92), do: ["color:var(--ansi-bright-green,#23d18b)"]
  defp code_to_css(93), do: ["color:var(--ansi-bright-yellow,#f5f543)"]
  defp code_to_css(94), do: ["color:var(--ansi-bright-blue,#3b8eea)"]
  defp code_to_css(95), do: ["color:var(--ansi-bright-magenta,#d670d6)"]
  defp code_to_css(96), do: ["color:var(--ansi-bright-cyan,#29b8db)"]
  defp code_to_css(97), do: ["color:var(--ansi-bright-white,#e5e5e5)"]

  # Bright background colors (100-107)
  defp code_to_css(100), do: ["background:var(--ansi-bright-black,#666666)"]
  defp code_to_css(101), do: ["background:var(--ansi-bright-red,#f14c4c)"]
  defp code_to_css(102), do: ["background:var(--ansi-bright-green,#23d18b)"]
  defp code_to_css(103), do: ["background:var(--ansi-bright-yellow,#f5f543)"]
  defp code_to_css(104), do: ["background:var(--ansi-bright-blue,#3b8eea)"]
  defp code_to_css(105), do: ["background:var(--ansi-bright-magenta,#d670d6)"]
  defp code_to_css(106), do: ["background:var(--ansi-bright-cyan,#29b8db)"]
  defp code_to_css(107), do: ["background:var(--ansi-bright-white,#e5e5e5)"]

  # Unknown codes -- ignored
  defp code_to_css(_), do: []

  defp parse_int(""), do: 0
  defp parse_int(s), do: String.to_integer(s)

  defp html_escape(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~S("), "&quot;")
  end
end
