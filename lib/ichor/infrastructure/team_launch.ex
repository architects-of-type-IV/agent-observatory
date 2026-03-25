defmodule Ichor.Infrastructure.TeamLaunch do
  @moduledoc """
  Lifecycle operations for launching and tearing down multi-agent tmux-backed teams.

  Orchestrates the named launch stages:
    1. Write prompt and script files for each agent
    2. `TeamLaunch.Session` -- create tmux session and windows
    3. Register agents in the fleet registry

  On failure, teardown cleans up any partially-created resources.
  """

  alias Ichor.Fleet.Supervisor, as: FleetSupervisor
  alias Ichor.Infrastructure.Registration
  alias Ichor.Infrastructure.TeamLaunch.Session
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

  defp do_launch(%TeamSpec{} = spec) do
    with {:ok, scripts} <- write_all(spec),
         :ok <- Session.create_all(spec, scripts),
         :ok <- register_all(spec) do
      {:ok, spec.session}
    end
  end

  @doc "Launch a single agent from the spec into an already-running tmux session."
  @spec launch_into_existing_session(TeamSpec.t(), String.t()) :: :ok | {:error, term()}
  def launch_into_existing_session(%TeamSpec{agents: [agent]} = spec, session) do
    with {:ok, scripts} <- write_all(spec),
         :ok <- Session.create_window(session, spec.cwd, agent, scripts),
         {:ok, _result} <- register_one(agent, session) do
      :ok
    end
  end

  @doc """
  Tear down a launched team: kill the tmux session, disband the fleet team,
  and remove prompt files. Idempotent -- missing session or prompt dir does not raise.
  """
  @spec teardown(TeamSpec.t()) :: :ok
  def teardown(%{session: session, team_name: team_name, prompt_dir: prompt_dir}) do
    teardown(session, team_name, prompt_dir)
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

  # --- Script writing ---

  defp write_all(%{prompt_dir: prompt_dir, agents: agents}) do
    Enum.reduce_while(agents, {:ok, %{}}, fn agent, {:ok, acc} ->
      case Script.write_agent_files(
             prompt_dir,
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

  # --- Agent registration ---

  defp register_all(%{session: session, agents: agents}) do
    agents
    |> Task.async_stream(
      fn agent -> Registration.register(agent, "#{session}:#{agent.window_name}") end,
      on_timeout: :kill_task
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, {:ok, _result}}, :ok -> {:cont, :ok}
      {:ok, {:error, reason}}, :ok -> {:halt, {:error, reason}}
      {:exit, reason}, :ok -> {:halt, {:error, reason}}
    end)
  end

  defp register_one(agent, session) do
    Registration.register(%{agent | session: session}, "#{session}:#{agent.window_name}")
  end
end
