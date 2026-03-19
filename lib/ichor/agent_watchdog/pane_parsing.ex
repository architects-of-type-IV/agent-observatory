defmodule Ichor.AgentWatchdog.PaneParser do
  @moduledoc """
  Pure helpers for tmux pane output diffing and signal pattern extraction.

  No side effects. All functions operate on plain strings and maps.
  """

  alias Ichor.Gateway.Channels.{SshTmux, Tmux}

  @capture_lines 30

  @doc """
  Return lines in `current` that follow the content of `prev`.

  Simple tail-diff: drops lines up to the length of prev, returns the remainder.
  If no new lines and content changed, returns the full current output.
  """
  @spec diff_output(String.t(), String.t()) :: String.t()
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

  @doc "Return `{target, capture_fn}` for an agent that has a tmux or ssh_tmux channel, else nil."
  @spec resolve_capture_target(map()) ::
          {String.t(), (String.t() -> {:ok, String.t()} | {:error, term()})} | nil
  def resolve_capture_target(%{channels: %{tmux: target}}) when is_binary(target) do
    {target, &Tmux.capture_pane(&1, lines: @capture_lines)}
  end

  def resolve_capture_target(%{channels: %{ssh_tmux: target}}) when is_binary(target) do
    {target, &SshTmux.capture_pane(&1, lines: @capture_lines)}
  end

  def resolve_capture_target(_), do: nil

  @doc "Match ICHOR_DONE pattern. Returns `{:ok, summary}` or `:nomatch`."
  @spec match_done(String.t()) :: {:ok, String.t()} | :nomatch
  def match_done(text) do
    case Regex.run(~r/ICHOR_DONE:\s*(.+)/, text) do
      [_, summary] -> {:ok, String.trim(summary)}
      nil -> :nomatch
    end
  end

  @doc "Match ICHOR_BLOCKED pattern. Returns `{:ok, reason}` or `:nomatch`."
  @spec match_blocked(String.t()) :: {:ok, String.t()} | :nomatch
  def match_blocked(text) do
    case Regex.run(~r/ICHOR_BLOCKED:\s*(.+)/, text) do
      [_, reason] -> {:ok, String.trim(reason)}
      nil -> :nomatch
    end
  end
end
