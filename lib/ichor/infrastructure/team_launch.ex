defmodule Ichor.Infrastructure.TeamLaunch do
  @moduledoc """
  Lifecycle operations for launching and tearing down multi-agent tmux-backed teams.
  """

  alias Ichor.Infrastructure.FleetSupervisor
  alias Ichor.Infrastructure.Registration
  alias Ichor.Infrastructure.TeamSpec
  alias Ichor.Infrastructure.Tmux.{Launcher, Script}

  @doc "Launch a full multi-agent team: creates tmux session, all windows, and registers all agents."
  @spec launch(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  def launch(%TeamSpec{} = spec) do
    with {:error, reason} <- do_launch(spec) do
      teardown(spec)
      {:error, reason}
    end
  end

  defp do_launch(%TeamSpec{agents: [first | rest]} = spec) do
    with {:ok, scripts} <- write_agent_files(spec),
         :ok <-
           Launcher.create_session(
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
           Launcher.create_window(
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
      case Launcher.create_window(
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
      case Script.write_agent_files(
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

  @doc """
  Tear down a launched team: kill the tmux session, disband the fleet team,
  and remove prompt files. Idempotent -- missing session or prompt dir does not raise.
  """
  @spec teardown(TeamSpec.t()) :: :ok
  def teardown(%TeamSpec{} = spec) do
    teardown(spec.session, spec.team_name, spec.prompt_dir)
  end

  @doc "Tear down by explicit parts rather than a spec struct. Same idempotent semantics."
  @spec teardown(String.t(), String.t(), String.t() | nil) :: :ok
  def teardown(session, team_name, prompt_dir) do
    _ = Launcher.kill_session(session)
    _ = FleetSupervisor.disband_team(team_name)

    if prompt_dir do
      Script.cleanup_dir(prompt_dir)
    end

    :ok
  end

  defp script_for!(scripts, window_name), do: Map.fetch!(scripts, window_name)
end
