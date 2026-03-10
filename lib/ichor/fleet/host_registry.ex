defmodule Ichor.Fleet.HostRegistry do
  @moduledoc """
  Tracks available BEAM nodes in the fleet. Each node represents a host
  that can run tmux sessions and AgentProcesses.

  Nodes register automatically when they connect to the cluster.
  Manual registration is also supported for pre-configuring hosts
  before they come online.

  Uses :pg (OTP process groups) for cluster-wide visibility.
  """

  use GenServer
  require Logger

  @pg_scope :ichor_agents
  @pg_group :ichor_hosts

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List all known hosts with their metadata."
  @spec list_hosts() :: [map()]
  def list_hosts do
    GenServer.call(__MODULE__, :list_hosts)
  end

  @doc "Get metadata for a specific node."
  @spec get_host(node()) :: map() | nil
  def get_host(node_name) do
    GenServer.call(__MODULE__, {:get_host, node_name})
  end

  @doc "Register a host manually with connection details."
  @spec register_host(node(), map()) :: :ok
  def register_host(node_name, metadata) do
    GenServer.call(__MODULE__, {:register, node_name, metadata})
  end

  @doc "Remove a host from the registry."
  @spec remove_host(node()) :: :ok
  def remove_host(node_name) do
    GenServer.call(__MODULE__, {:remove, node_name})
  end

  @doc "Check if a node is connected and available for spawning."
  @spec available?(node()) :: boolean()
  def available?(node_name) do
    node_name == Node.self() or node_name in Node.list()
  end

  @doc "Get the local node's host entry."
  @spec local_host() :: map()
  def local_host do
    %{
      node: Node.self(),
      hostname: hostname(),
      status: :connected,
      capabilities: [:tmux, :spawn],
      connected_at: nil,
      metadata: %{}
    }
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(_opts) do
    # Join the :pg group so other nodes can discover us
    :pg.join(@pg_scope, @pg_group, self())

    # Monitor node connections/disconnections
    :net_kernel.monitor_nodes(true, node_type: :visible)

    # Build initial state from connected nodes
    hosts =
      [Node.self() | Node.list()]
      |> Enum.map(fn node -> {node, host_entry(node, :connected)} end)
      |> Map.new()

    Logger.info("[HostRegistry] Started. Known hosts: #{map_size(hosts)}")
    {:ok, %{hosts: hosts}}
  end

  @impl true
  def handle_call(:list_hosts, _from, state) do
    hosts = Map.values(state.hosts)
    {:reply, hosts, state}
  end

  def handle_call({:get_host, node_name}, _from, state) do
    {:reply, Map.get(state.hosts, node_name), state}
  end

  def handle_call({:register, node_name, metadata}, _from, state) do
    status = registration_status(node_name)
    entry = host_entry(node_name, status) |> Map.put(:metadata, metadata)
    hosts = Map.put(state.hosts, node_name, entry)

    broadcast_hosts_changed()
    {:reply, :ok, %{state | hosts: hosts}}
  end

  def handle_call({:remove, node_name}, _from, state) do
    hosts = Map.delete(state.hosts, node_name)

    broadcast_hosts_changed()
    {:reply, :ok, %{state | hosts: hosts}}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("[HostRegistry] Node connected: #{node}")
    entry = host_entry(node, :connected)
    hosts = Map.put(state.hosts, node, entry)

    broadcast_hosts_changed()
    {:noreply, %{state | hosts: hosts}}
  end

  def handle_info({:nodedown, node, _info}, state) do
    Logger.info("[HostRegistry] Node disconnected: #{node}")

    hosts =
      Map.update(state.hosts, node, nil, fn entry ->
        %{entry | status: :disconnected}
      end)

    broadcast_hosts_changed()
    {:noreply, %{state | hosts: hosts}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Private ────────────────────────────────────────────────────────

  defp host_entry(node, status) do
    %{
      node: node,
      hostname: node_hostname(node),
      status: status,
      capabilities: [:tmux, :spawn],
      connected_at: connected_timestamp(status),
      metadata: %{}
    }
  end

  defp connected_timestamp(:connected), do: DateTime.utc_now()
  defp connected_timestamp(_), do: nil

  defp registration_status(node_name) do
    case available?(node_name) do
      true -> :connected
      false -> :registered
    end
  end

  defp node_hostname(node) do
    node
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
  end

  defp hostname do
    node_hostname(Node.self())
  end

  defp broadcast_hosts_changed do
    Ichor.Signals.emit(:hosts_changed, %{})
  end
end
