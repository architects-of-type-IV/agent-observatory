defmodule Observatory.Fleet.TeamSupervisor do
  @moduledoc """
  A team is a DynamicSupervisor. Its children are AgentProcess GenServers.
  The supervisor's restart strategy governs how member failures propagate.

  Teams register in `Observatory.Fleet.TeamRegistry` for discovery.
  """

  use DynamicSupervisor
  require Logger

  @team_registry Observatory.Fleet.TeamRegistry

  defstruct [:name, :project, :strategy, :lead_id, metadata: %{}]

  # ── Public API ──────────────────────────────────────────────────────

  @doc "Start a team supervisor and register it in the team registry."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    DynamicSupervisor.start_link(__MODULE__, opts, name: via(name))
  end

  @doc "Spawn a new agent as a member of this team."
  @spec spawn_member(String.t(), keyword()) :: DynamicSupervisor.on_start_child()
  def spawn_member(team_name, agent_opts) do
    agent_opts = Keyword.put(agent_opts, :team, team_name)
    DynamicSupervisor.start_child(via(team_name), {Observatory.Fleet.AgentProcess, agent_opts})
  end

  @doc "Terminate a specific member by agent ID."
  @spec terminate_member(String.t(), String.t()) :: :ok | {:error, :not_found}
  def terminate_member(team_name, agent_id) do
    case Registry.lookup(Observatory.Fleet.ProcessRegistry, agent_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(via(team_name), pid)
      [] -> {:error, :not_found}
    end
  end

  @doc "List all child specs (members) of this team."
  @spec members(String.t()) :: [DynamicSupervisor.child()]
  def members(team_name) do
    DynamicSupervisor.which_children(via(team_name))
  end

  @doc "Count living members."
  @spec member_count(String.t()) :: non_neg_integer()
  def member_count(team_name) do
    case members(team_name) do
      children when is_list(children) -> length(children)
      _ -> 0
    end
  end

  @doc "Get IDs of all members in this team from the agent registry."
  @spec member_ids(String.t()) :: [String.t()]
  def member_ids(team_name) do
    Observatory.Fleet.AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:team] == team_name end)
    |> Enum.map(fn {id, _meta} -> id end)
  end

  @doc "Check if a team exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(team_name) do
    case Registry.lookup(@team_registry, team_name) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "List all registered team names with metadata."
  @spec list_all() :: [{String.t(), map()}]
  def list_all do
    Registry.select(@team_registry, [{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  defp via(name), do: {:via, Registry, {@team_registry, name, %{}}}

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    project = Keyword.get(opts, :project)

    Registry.update_value(@team_registry, name, fn _ ->
      %{project: project, strategy: strategy}
    end)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "fleet:lifecycle",
      {:team_created, name, %{project: project, strategy: strategy}}
    )

    Logger.info("[TeamSupervisor] Created team #{name} (strategy=#{strategy})")
    DynamicSupervisor.init(strategy: strategy, max_restarts: 5, max_seconds: 60)
  end
end
