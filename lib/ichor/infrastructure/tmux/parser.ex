defmodule Ichor.Infrastructure.Tmux.Parser do
  @moduledoc """
  Parses raw tmux output into structured data.

  Isolates all string-splitting and field extraction so the transport and
  listing functions in the parent `Tmux` module stay free of parsing details.
  """

  @doc """
  Parse a single line from `tmux list-panes -F "\#{pane_id}\t\#{session_name}\t\#{pane_title}\t\#{pane_pid}"`.

  Returns a map with keys `pane_id`, `session`, `title`, and `pid`, or `nil`
  if the line cannot be parsed.
  """
  @spec parse_pane_line(String.t()) :: map() | nil
  def parse_pane_line(line) do
    case String.split(line, "\t") do
      [pane_id, session, title, pid] ->
        %{pane_id: pane_id, session: session, title: title, pid: pid}

      [pane_id, session, title] ->
        %{pane_id: pane_id, session: session, title: title, pid: nil}

      _ ->
        nil
    end
  end

  @doc "Split a newline-delimited tmux output string into a list of trimmed lines."
  @spec split_lines(String.t()) :: [String.t()]
  def split_lines(output), do: String.split(output, "\n", trim: true)
end
