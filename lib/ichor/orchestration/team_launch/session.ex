defmodule Ichor.Orchestration.TeamLaunch.Session do
  @moduledoc """
  Manages tmux session and window creation for team launches.

  Delegates low-level command execution to `Tmux.Launcher`.  This module is
  responsible for the team-level orchestration (e.g. creating the session with
  the first agent window, then creating subsequent windows in order).
  """

  alias Ichor.Infrastructure.Tmux.Launcher

  @doc """
  Create the tmux session with the first agent's window, then add the remaining
  agent windows.

  `scripts` is a `window_name => script_path` map produced by
  `TeamLaunch.Scripts.write_all/1`.
  """
  @spec create_all(map(), map()) :: :ok | {:error, term()}
  def create_all(%{session: session, cwd: cwd, agents: [first | rest]}, scripts) do
    with :ok <-
           Launcher.create_session(
             session,
             cwd,
             first.window_name,
             Map.fetch!(scripts, first.window_name)
           ) do
      create_remaining_windows(session, cwd, rest, scripts)
    end
  end

  @doc "Add a single window to an existing session for `agent`."
  @spec create_window(String.t(), String.t(), map(), map()) :: :ok | {:error, term()}
  def create_window(session, cwd, agent, scripts) do
    Launcher.create_window(
      session,
      agent.window_name,
      cwd,
      Map.fetch!(scripts, agent.window_name)
    )
  end

  defp create_remaining_windows(session, cwd, agents, scripts) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      case Launcher.create_window(
             session,
             agent.window_name,
             cwd,
             Map.fetch!(scripts, agent.window_name)
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
