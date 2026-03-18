defmodule Ichor.Fleet.Lifecycle.TmuxLauncher do
  @moduledoc """
  Shared tmux session and window lifecycle operations.
  """

  alias Ichor.Gateway.Channels.Tmux

  @spec create_session(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_session(session, cwd, window_name, command) do
    case Tmux.run_command([
           "new-session",
           "-d",
           "-s",
           session,
           "-c",
           cwd,
           "-n",
           window_name,
           command
         ]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec create_window(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_window(session, window_name, cwd, command) do
    case Tmux.run_command(["new-window", "-t", session, "-n", window_name, "-c", cwd, command]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec kill_session(String.t()) :: :ok | {:error, term()}
  def kill_session(session) do
    case Tmux.run_command(["kill-session", "-t", session]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec send_exit(String.t()) :: :ok | {:error, term()}
  def send_exit(tmux_target) do
    case Tmux.run_command(["send-keys", "-t", tmux_target, "/exit", "Enter"]) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec available?(String.t()) :: boolean()
  def available?(target), do: Tmux.available?(target)

  @spec list_sessions() :: [String.t()]
  def list_sessions, do: Tmux.list_sessions()
end
