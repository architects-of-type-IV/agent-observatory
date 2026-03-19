defmodule Ichor.Control.Lifecycle.TeamLaunch do
  @moduledoc """
  Lifecycle operations for launching multi-agent tmux-backed teams.
  """

  alias Ichor.Control.Lifecycle.Registration
  alias Ichor.Control.Lifecycle.TeamSpec
  alias Ichor.Control.Lifecycle.TmuxLauncher
  alias Ichor.Control.Lifecycle.TmuxScript

  @doc "Launch a full multi-agent team: creates tmux session, all windows, and registers all agents."
  @spec launch(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  def launch(%TeamSpec{agents: [first | rest]} = spec) do
    with {:ok, scripts} <- write_agent_files(spec),
         :ok <-
           TmuxLauncher.create_session(
             spec.session,
             spec.cwd,
             first.window_name,
             script_for!(scripts, first.window_name)
           ),
         :ok <- create_windows(spec, rest, scripts),
         :ok <- register_agents(spec) do
      {:ok, spec.session}
    end
  end

  @doc "Launch a single agent from the spec into an already-running tmux session."
  @spec launch_into_existing_session(TeamSpec.t(), String.t()) :: :ok | {:error, term()}
  def launch_into_existing_session(%TeamSpec{agents: [agent]} = spec, session) do
    with {:ok, scripts} <- write_agent_files(spec),
         :ok <-
           TmuxLauncher.create_window(
             session,
             agent.window_name,
             spec.cwd,
             script_for!(scripts, agent.window_name)
           ),
         {:ok, _result} <-
           Registration.register(%{agent | session: session}, "#{session}:#{agent.window_name}") do
      :ok
    end
  end

  defp create_windows(spec, agents, scripts) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      case TmuxLauncher.create_window(
             spec.session,
             agent.window_name,
             spec.cwd,
             script_for!(scripts, agent.window_name)
           ) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp register_agents(%TeamSpec{} = spec) do
    Enum.reduce_while(spec.agents, :ok, fn agent, :ok ->
      case Registration.register(agent, "#{spec.session}:#{agent.window_name}") do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp write_agent_files(%TeamSpec{} = spec) do
    Enum.reduce_while(spec.agents, {:ok, %{}}, fn agent, {:ok, acc} ->
      case TmuxScript.write_agent_files(
             spec.prompt_dir,
             agent.window_name,
             agent.prompt || "",
             agent.model || "sonnet",
             agent.capability || "builder"
           ) do
        {:ok, %{script_path: script_path}} ->
          {:cont, {:ok, Map.put(acc, agent.window_name, script_path)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp script_for!(scripts, window_name), do: Map.fetch!(scripts, window_name)
end
