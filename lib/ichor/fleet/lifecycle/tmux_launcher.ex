defmodule Ichor.Fleet.Lifecycle.TmuxLauncher do
  @moduledoc """
  Shared tmux session and window lifecycle operations.
  """

  alias Ichor.Fleet.TmuxHelpers

  @spec create_session(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_session(session, cwd, window_name, command) do
    run_command(["new-session", "-d", "-s", session, "-c", cwd, "-n", window_name, command])
  end

  @spec create_window(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_window(session, window_name, cwd, command) do
    run_command(["new-window", "-t", session, "-n", window_name, "-c", cwd, command])
  end

  @spec kill_session(String.t()) :: :ok | {:error, term()}
  def kill_session(session), do: run_command(["kill-session", "-t", session])

  @spec send_exit(String.t()) :: :ok | {:error, term()}
  def send_exit(tmux_target), do: run_command(["send-keys", "-t", tmux_target, "/exit", "Enter"])

  @spec available?(String.t()) :: boolean()
  def available?(target), do: match?({:ok, _}, tmux(["has-session", "-t", target]))

  @spec list_sessions() :: [String.t()]
  def list_sessions do
    case tmux(["list-sessions", "-F", "\#{session_name}"]) do
      {:ok, output} -> String.split(output, "\n", trim: true)
      {:error, _reason} -> []
    end
  end

  defp run_command(args) do
    case tmux(args) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp tmux(args) do
    case System.cmd("tmux", TmuxHelpers.tmux_args() ++ args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:tmux_failed, code, String.trim(output)}}
    end
  end
end
