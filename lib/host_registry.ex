defmodule HostRegistry do
  @moduledoc """
  Tracks the BEAM nodes available to run work.

  Each entry is a host that can accept jobs — in the system this came from, a
  node running tmux sessions and agent processes. Nodes register themselves
  automatically as they join the cluster, and can also be registered ahead of
  time so a host is known before it comes online.

  ## Two sources of truth, on purpose

  Membership is *observed*, via `:net_kernel.monitor_nodes/2`, rather than
  declared. A node that connects appears; a node that drops is marked
  `:disconnected` rather than deleted, because "was here and left" is worth
  knowing — a silently vanishing entry looks identical to one that never
  existed.

  `available?/1` deliberately does not consult the registry. It asks the VM
  directly, so a stale entry can never make an unreachable node look usable.
  Use `list_hosts/0` to see what is known, and `available?/1` to decide whether
  to send work.

  ## Cluster visibility

  The registry joins a `:pg` process group, so registries on other nodes can
  discover each other through `members/0` with no central arbiter.

  ## Setup

      children = [HostRegistry]

      config :host_registry,
        capabilities: [:tmux, :spawn],
        notifier: MyApp.HostNotifier

  ## Example

      HostRegistry.list_hosts()
      #=> [%HostRegistry.Host{node: :"app@box-1", status: :connected, ...}]

      HostRegistry.register_host(:"worker@box-2", %{region: "eu"})
      HostRegistry.available?(:"worker@box-2")
  """

  use GenServer

  require Logger

  alias HostRegistry.Host

  @default_scope :host_registry
  @default_group :hosts

  @doc "Start the registry."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Every known host, connected or not."
  @spec list_hosts() :: [Host.t()]
  def list_hosts, do: GenServer.call(__MODULE__, :list_hosts)

  @doc "The known hosts that are currently connected."
  @spec list_connected() :: [Host.t()]
  def list_connected, do: Enum.filter(list_hosts(), &(&1.status == :connected))

  @doc "One host by node name, or `nil`."
  @spec get_host(node()) :: Host.t() | nil
  def get_host(node_name), do: GenServer.call(__MODULE__, {:get_host, node_name})

  @doc """
  Register a host, with arbitrary metadata.

  Works for a node that has not connected yet — it lands as `:registered` and
  flips to `:connected` when it joins. Re-registering an existing host replaces
  its metadata.
  """
  @spec register_host(node(), map()) :: :ok
  def register_host(node_name, metadata \\ %{}),
    do: GenServer.call(__MODULE__, {:register, node_name, metadata})

  @doc "Forget a host entirely."
  @spec remove_host(node()) :: :ok
  def remove_host(node_name), do: GenServer.call(__MODULE__, {:remove, node_name})

  @doc """
  Whether a node is reachable right now.

  Asks the VM, not the registry, so a stale entry cannot make an unreachable
  node look usable.
  """
  @spec available?(node()) :: boolean()
  def available?(node_name), do: node_name == Node.self() or node_name in Node.list()

  @doc "This node's own entry."
  @spec local_host() :: Host.t()
  def local_host, do: Host.new(Node.self(), :connected, capabilities: capabilities())

  @doc """
  Registry processes across the cluster, including this one.

  Backed by `:pg`, so it reflects whichever nodes are currently connected.
  """
  @spec members() :: [pid()]
  def members, do: :pg.get_members(scope(), group())

  # Server

  @impl true
  def init(_opts) do
    ensure_pg_scope()
    :pg.join(scope(), group(), self())
    :net_kernel.monitor_nodes(true, node_type: :visible)

    hosts =
      [Node.self() | Node.list()]
      |> Map.new(&{&1, Host.new(&1, :connected, capabilities: capabilities())})

    Logger.info("[HostRegistry] Started. Known hosts: #{map_size(hosts)}")
    {:ok, %{hosts: hosts}}
  end

  @impl true
  def handle_call(:list_hosts, _from, state), do: {:reply, Map.values(state.hosts), state}

  def handle_call({:get_host, node_name}, _from, state),
    do: {:reply, Map.get(state.hosts, node_name), state}

  def handle_call({:register, node_name, metadata}, _from, state) do
    status = if available?(node_name), do: :connected, else: :registered
    entry = Host.new(node_name, status, capabilities: capabilities(), metadata: metadata)

    {:reply, :ok, put_host(state, node_name, entry)}
  end

  def handle_call({:remove, node_name}, _from, state) do
    hosts = Map.delete(state.hosts, node_name)
    notify(hosts)
    {:reply, :ok, %{state | hosts: hosts}}
  end

  @impl true
  def handle_info({:nodeup, node, _info}, state) do
    Logger.info("[HostRegistry] Node connected: #{node}")

    # Keep any metadata from a prior registration; only the liveness changes.
    entry =
      case Map.get(state.hosts, node) do
        nil ->
          Host.new(node, :connected, capabilities: capabilities())

        existing ->
          %{existing | status: :connected, connected_at: DateTime.utc_now()}
      end

    {:noreply, put_host(state, node, entry)}
  end

  def handle_info({:nodedown, node, _info}, state) do
    Logger.info("[HostRegistry] Node disconnected: #{node}")

    # Only mark a node we already knew about. Map.update/4 with a nil default
    # would otherwise insert a nil entry for an unknown node and break every
    # later read of the host list.
    case Map.fetch(state.hosts, node) do
      {:ok, entry} -> {:noreply, put_host(state, node, %{entry | status: :disconnected})}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private

  defp put_host(state, node_name, entry) do
    hosts = Map.put(state.hosts, node_name, entry)
    notify(hosts)
    %{state | hosts: hosts}
  end

  defp notify(hosts), do: notifier().hosts_changed(Map.values(hosts))

  # `:pg` needs its scope running before anything can join. The host application
  # may already have started it; if not, start it here so the registry works
  # without extra wiring.
  defp ensure_pg_scope do
    case :pg.start_link(scope()) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> Logger.warning("[HostRegistry] pg scope failed: #{inspect(reason)}")
    end
  end

  defp scope, do: Application.get_env(:host_registry, :pg_scope, @default_scope)
  defp group, do: Application.get_env(:host_registry, :pg_group, @default_group)

  defp capabilities, do: Application.get_env(:host_registry, :capabilities, [])

  defp notifier,
    do: Application.get_env(:host_registry, :notifier, HostRegistry.Notifier.Noop)
end
