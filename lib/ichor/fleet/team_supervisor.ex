defmodule Ichor.Fleet.TeamSupervisor do
  @moduledoc """
  A team is a DynamicSupervisor. Its children are AgentProcess GenServers.
  The supervisor's restart strategy governs how member failures propagate.

  Teams register in `Ichor.Registry` via `{:team, name}` for discovery.
  """

  use DynamicSupervisor

  alias Ichor.Fleet.AgentProcess

  @team_registry Ichor.Registry
  @pg_scope :ichor_agents

  @enforce_keys [:name]
  defstruct [:name, :project, :strategy, :lead_id, metadata: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          project: String.t() | nil,
          strategy: atom() | nil,
          lead_id: String.t() | nil,
          metadata: map()
        }

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
    DynamicSupervisor.start_child(via(team_name), {AgentProcess, agent_opts})
  end

  @doc "Terminate a specific member by agent ID."
  @spec terminate_member(String.t(), String.t()) :: :ok | {:error, :not_found}
  def terminate_member(team_name, agent_id) do
    case Registry.lookup(Ichor.Registry, {:agent, agent_id}) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(via(team_name), pid)
      [] -> {:error, :not_found}
    end
  end

  @doc "List all child specs (members) of this team."
  @spec members(String.t()) :: [
          {:undefined, :restarting | pid(), :supervisor | :worker, :dynamic | [atom()]}
        ]
  def members(team_name) do
    DynamicSupervisor.which_children(via(team_name))
  end

  @doc "Count living members."
  @spec member_count(String.t()) :: non_neg_integer()
  def member_count(team_name) do
    members(team_name) |> length()
  end

  @doc "Get IDs of all members in this team from the agent registry."
  @spec member_ids(String.t()) :: [String.t()]
  def member_ids(team_name) do
    for {id, meta} <- AgentProcess.list_all(), meta[:team] == team_name, do: id
  end

  @doc "Check if a team exists."
  @spec exists?(String.t()) :: boolean()
  def exists?(team_name) do
    case Registry.lookup(@team_registry, {:team, team_name}) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "List all registered team names with metadata (local node)."
  @spec list_all() :: [{String.t(), map()}]
  def list_all do
    Registry.select(@team_registry, [
      {{{:team, :"$1"}, :_, :"$3"}, [], [{{:"$1", :"$3"}}]}
    ])
  end

  defp via(name), do: {:via, Registry, {@team_registry, {:team, name}, %{}}}

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    project = Keyword.get(opts, :project)

    Registry.update_value(@team_registry, {:team, name}, fn _ ->
      %{project: project, strategy: strategy}
    end)

    Ichor.Signals.emit(:team_created, %{name: name, project: project, strategy: strategy})

    # Join :pg group for cluster-wide team discovery
    :pg.join(@pg_scope, {:team, name}, self())

    DynamicSupervisor.init(strategy: strategy, max_restarts: 5, max_seconds: 60)
  end
end
