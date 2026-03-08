defmodule Observatory.Fleet.FleetSupervisor do
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
  require Logger

  # ── Public API ──────────────────────────────────────────────────────

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
  def create_team(opts) do
    name = Keyword.fetch!(opts, :name)

    if Observatory.Fleet.TeamSupervisor.exists?(name) do
      {:error, :already_exists}
    else
      DynamicSupervisor.start_child(__MODULE__, {Observatory.Fleet.TeamSupervisor, opts})
    end
  end

  @doc "Disband a team, terminating all its members."
  def disband_team(team_name) do
    case Registry.lookup(Observatory.Fleet.TeamRegistry, team_name) do
      [{pid, _}] ->
        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "fleet:lifecycle",
          {:team_disbanded, team_name}
        )

        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc "Spawn a standalone agent (not part of any team)."
  def spawn_agent(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Observatory.Fleet.AgentProcess, opts})
  end

  @doc "Terminate a standalone agent."
  def terminate_agent(agent_id) do
    case Registry.lookup(Observatory.Fleet.ProcessRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @doc "List all teams and standalone agents."
  def status do
    children = DynamicSupervisor.which_children(__MODULE__)
    teams = Observatory.Fleet.TeamSupervisor.list_all()
    agents = Observatory.Fleet.AgentProcess.list_all()

    %{
      child_count: length(children),
      teams: teams,
      agents: agents
    }
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
