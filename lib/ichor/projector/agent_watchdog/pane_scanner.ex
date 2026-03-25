defmodule Ichor.Projector.AgentWatchdog.PaneScanner do
  @moduledoc """
  Tmux pane capture and signal parsing. Scans agent output for done/blocked patterns.

  All functions are pure or limit side effects to the tmux capture call. Signal
  emission (Ichor.Signals.emit) and AgentProcess state updates remain in the caller.
  """

  alias Ichor.Infrastructure.Tmux
  alias Ichor.Infrastructure.Tmux.Ssh, as: SshTmux

  @capture_lines 30

  @doc """
  Resolves the capture target and capture function for an agent.

  Returns `{target, capture_fn}` when the agent has a tmux or ssh_tmux channel
  with a valid target string, or `nil` when no scan is possible.
  """
  @spec resolve_capture_target(agent :: map()) ::
          {String.t(), (String.t() -> {:ok, String.t()} | {:error, any()})} | nil
  def resolve_capture_target(%{channels: %{tmux: target}}) when is_binary(target) do
    if capture_target?(target), do: {target, &Tmux.capture_pane(&1, lines: @capture_lines)}
  end

  def resolve_capture_target(%{channels: %{ssh_tmux: target}}) when is_binary(target) do
    if capture_target?(target), do: {target, &SshTmux.capture_pane(&1, lines: @capture_lines)}
  end

  def resolve_capture_target(_), do: nil

  @doc """
  Returns true when `target` is a valid tmux pane reference.

  Accepts pane IDs (starting with `%`) and `session:window.pane` style targets.
  """
  @spec capture_target?(target :: String.t()) :: boolean()
  def capture_target?("%" <> _), do: true
  def capture_target?(target) when is_binary(target), do: String.contains?(target, ":")

  @doc """
  Computes the diff between two consecutive pane captures.

  Returns only lines that appear after the previous output ends, or the full
  current output when the captures share no overlap.
  """
  @spec diff_output(prev :: String.t(), current :: String.t()) :: String.t()
  def diff_output(prev, current) do
    prev_lines = String.split(prev, "\n", trim: true)
    curr_lines = String.split(current, "\n", trim: true)

    overlap = length(prev_lines)

    if overlap > 0 and length(curr_lines) > overlap do
      curr_lines
      |> Enum.drop(overlap)
      |> Enum.join("\n")
    else
      if prev == current, do: "", else: current
    end
  end

  @doc """
  Attempts to match an `ICHOR_<token>: <value>` marker in `text`.

  Returns `{:ok, value}` on match, `:nomatch` otherwise.
  """
  @spec match_marker(token :: String.t(), text :: String.t()) :: {:ok, String.t()} | :nomatch
  def match_marker(token, text) do
    case Regex.run(~r/ICHOR_#{token}:\s*(.+)/, text) do
      [_, value] -> {:ok, String.trim(value)}
      nil -> :nomatch
    end
  end

  @doc "Attempts to match an `ICHOR_DONE: <summary>` marker. Returns `{:ok, summary}` or `:nomatch`."
  @spec match_done(text :: String.t()) :: {:ok, String.t()} | :nomatch
  def match_done(text), do: match_marker("DONE", text)

  @doc "Attempts to match an `ICHOR_BLOCKED: <reason>` marker. Returns `{:ok, reason}` or `:nomatch`."
  @spec match_blocked(text :: String.t()) :: {:ok, String.t()} | :nomatch
  def match_blocked(text), do: match_marker("BLOCKED", text)
end
