defmodule TmuxChannel.Launcher do
  @moduledoc """
  Session and window lifecycle operations.

  Unlike `TmuxChannel`, which reads across every reachable server, the launcher
  targets exactly one server — the explicit socket when it exists, otherwise the
  named server. Creation has to be deterministic: "whichever server answered
  first" is fine for a query and wrong for `new-session`.
  """

  @doc "Create a detached session whose first window runs `command`."
  @spec create_session(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_session(session, cwd, window_name, command) do
    run(["new-session", "-d", "-s", session, "-c", cwd, "-n", window_name, command])
  end

  @doc "Add a window running `command` to an existing session."
  @spec create_window(String.t(), String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def create_window(session, window_name, cwd, command) do
    run(["new-window", "-t", session, "-n", window_name, "-c", cwd, command])
  end

  @doc "Kill a session and all of its windows."
  @spec kill_session(String.t()) :: :ok | {:error, term()}
  def kill_session(session), do: run(["kill-session", "-t", session])

  @doc "Send `text` followed by Enter to a target, to stop a process gracefully."
  @spec send_exit(String.t(), String.t()) :: :ok | {:error, term()}
  def send_exit(target, text \\ "/exit"), do: run(["send-keys", "-t", target, text, "Enter"])

  @doc "Whether a session exists on the primary server."
  @spec available?(String.t()) :: boolean()
  def available?(target), do: match?({:ok, _}, tmux(["has-session", "-t", target]))

  @doc "List session names on the primary server."
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    case tmux(["list-sessions", "-F", "\#{session_name}"]) do
      {:ok, output} -> TmuxChannel.Parser.split_lines(output)
      {:error, _reason} -> []
    end
  end

  @doc """
  The single server this module targets.

  `["-S", socket]` when the configured socket file exists, otherwise
  `["-L", server_name]`.
  """
  @spec primary_server_args() :: [String.t()]
  def primary_server_args do
    socket = TmuxChannel.Config.socket_path()

    if File.exists?(socket) do
      ["-S", socket]
    else
      ["-L", TmuxChannel.Config.server_name()]
    end
  end

  defp run(args) do
    case tmux(args) do
      {:ok, _output} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp tmux(args), do: TmuxChannel.Command.run(primary_server_args() ++ args)
end
