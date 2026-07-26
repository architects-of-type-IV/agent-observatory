defmodule TmuxChannel.Parser do
  @moduledoc """
  Parsers for tmux's tab-delimited `-F` format output.

  Kept separate from command execution so the parsing rules are testable
  without a running tmux server.
  """

  @typedoc "A single pane as reported by `list-panes`."
  @type pane :: %{
          pane_id: String.t(),
          session: String.t(),
          title: String.t(),
          pid: String.t() | nil
        }

  @doc "Split tmux output into non-empty lines."
  @spec split_lines(String.t()) :: [String.t()]
  def split_lines(output), do: String.split(output, "\n", trim: true)

  @doc """
  Parse one `list-panes` line into a pane map.

  Accepts the four-field form (`pane_id`, `session`, `title`, `pane_pid`) and
  the three-field form without a pid. Returns `nil` for anything else, so
  malformed lines are dropped rather than crashing the listing.
  """
  @spec parse_pane_line(String.t()) :: pane() | nil
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

  @doc "Parse full `list-panes` output, dropping malformed lines."
  @spec parse_panes(String.t()) :: [pane()]
  def parse_panes(output) do
    output
    |> split_lines()
    |> Enum.map(&parse_pane_line/1)
    |> Enum.reject(&is_nil/1)
  end
end
