defmodule Ichor.Infrastructure.FleetSupervisor do
  @moduledoc """
  Top-level DynamicSupervisor for the fleet. Holds team supervisors and
  standalone agent processes (agents not assigned to any team).

  This is the root of the BEAM-native agent hierarchy:

      FleetSupervisor (DynamicSupervisor)
        +-- TeamSupervisor "squad-alpha" (DynamicSupervisor)
        |     +-- AgentProcess "lead-1"
        |     +-- AgentProcess "worker-1"
        +-- TeamSupervisor "squad-beta"
        |     +-- AgentProcess "coord-1"
        +-- AgentProcess "standalone-scout"    # no team
  """

  use DynamicSupervisor

  alias Ichor.Infrastructure.{AgentProcess, TeamSupervisor}

  @doc "Start the fleet supervisor."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Create a new team. Returns `{:ok, pid}` or `{:error, reason}`.

  Options:
    - `name` (required) - team name
    - `strategy` - supervision strategy (:one_for_one | :rest_for_one | :one_for_all)
    - `project` - project key or path
  """
  @spec create_team(keyword()) :: DynamicSupervisor.on_start_child() | {:error, :already_exists}
  def create_team(opts) do
    name = Keyword.fetch!(opts, :name)

    if TeamSupervisor.exists?(name) do
      {:error, :already_exists}
    else
      DynamicSupervisor.start_child(__MODULE__, {TeamSupervisor, opts})
    end
  end

  @doc "Disband a team, terminating all its members."
  @spec disband_team(String.t()) :: :ok | {:error, :not_found}
  def disband_team(team_name) do
    case Registry.lookup(Ichor.Registry, {:team, team_name}) do
      [{pid, _}] ->
        result = DynamicSupervisor.terminate_child(__MODULE__, pid)

        Ichor.Signals.emit(:team_disbanded, %{
          team_name: team_name,
          pid: inspect(pid),
          result: inspect(result)
        })

        result

      [] ->
        Ichor.Signals.emit(:team_disbanded, %{team_name: team_name, result: "not_found"})
        {:error, :not_found}
    end
  end

  @doc "Spawn a standalone agent (not part of any team)."
  @spec spawn_agent(keyword()) :: DynamicSupervisor.on_start_child()
  def spawn_agent(opts) do
    DynamicSupervisor.start_child(__MODULE__, {AgentProcess, opts})
  end

  @doc "Terminate a standalone agent by ID."
  @spec terminate_agent(String.t()) :: :ok | {:error, :not_found}
  def terminate_agent(agent_id) do
    case Registry.lookup(Ichor.Registry, {:agent, agent_id}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
