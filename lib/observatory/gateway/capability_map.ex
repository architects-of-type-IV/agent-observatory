defmodule Observatory.Gateway.CapabilityMap do
  @moduledoc """
  Tracks registered agents and their capabilities. Agents are added via
  `register_agent/3` and removed either explicitly or by HeartbeatManager
  eviction via `remove_agent/1`.
  """

  use GenServer

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register or update an agent with its capabilities and cluster."
  def register_agent(agent_id, capabilities, cluster_id) do
    GenServer.call(__MODULE__, {:register, agent_id, capabilities, cluster_id})
  end

  @doc "Remove an agent from the capability registry."
  def remove_agent(agent_id) do
    GenServer.call(__MODULE__, {:remove, agent_id})
  end

  @doc "Get agent info or nil if not registered."
  def get_agent(agent_id) do
    GenServer.call(__MODULE__, {:get, agent_id})
  end

  @doc "List all registered agents."
  def list_agents do
    GenServer.call(__MODULE__, :list)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, agent_id, capabilities, cluster_id}, _from, state) do
    entry = %{
      capabilities: capabilities,
      cluster_id: cluster_id,
      registered_at: DateTime.utc_now()
    }

    {:reply, :ok, Map.put(state, agent_id, entry)}
  end

  def handle_call({:remove, agent_id}, _from, state) do
    {:reply, :ok, Map.delete(state, agent_id)}
  end

  def handle_call({:get, agent_id}, _from, state) do
    {:reply, Map.get(state, agent_id), state}
  end

  def handle_call(:list, _from, state) do
    {:reply, state, state}
  end
end
