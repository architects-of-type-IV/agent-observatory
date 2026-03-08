defmodule Observatory.Fleet.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is pluggable via the Delivery module.
  """

  use GenServer
  require Logger

  alias Observatory.Fleet.AgentProcess.Delivery

  @max_message_buffer 200
  @type_iv_registry Observatory.Fleet.ProcessRegistry
  @pg_scope :observatory_agents

  @type status :: :initializing | :active | :paused | :terminating

  @type t :: %__MODULE__{
          id: String.t(),
          pid: pid() | nil,
          role: atom(),
          team: String.t() | nil,
          backend: map() | nil,
          capabilities: [atom()],
          instructions: String.t() | nil,
          status: status(),
          spawned_at: DateTime.t() | nil,
          metadata: map(),
          messages: [map()],
          unread: [map()]
        }

  defstruct [
    :id,
    :pid,
    :role,
    :team,
    :backend,
    :capabilities,
    :instructions,
    :status,
    :spawned_at,
    metadata: %{},
    messages: [],
    unread: []
  ]

  # ── Public API ──────────────────────────────────────────────────────

  @doc "Start an agent process and register it in the fleet registry."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc "Send a message to this agent. Non-blocking."
  @spec send_message(String.t(), map() | String.t()) :: :ok
  def send_message(agent_id, message) when is_binary(agent_id) do
    GenServer.cast(via(agent_id), {:message, message})
  end

  @doc "Retrieve the agent's current state."
  @spec get_state(String.t()) :: t()
  def get_state(agent_id) do
    GenServer.call(via(agent_id), :get_state)
  end

  @doc "Retrieve and clear unread messages (for MCP check_inbox compatibility)."
  @spec get_unread(String.t()) :: [map()]
  def get_unread(agent_id) do
    GenServer.call(via(agent_id), :get_unread)
  end

  @doc "Pause the agent (stops backend delivery, buffers messages)."
  @spec pause(String.t()) :: :ok
  def pause(agent_id) do
    GenServer.call(via(agent_id), :pause)
  end

  @doc "Resume a paused agent (delivers buffered messages)."
  @spec resume(String.t()) :: :ok
  def resume(agent_id) do
    GenServer.call(via(agent_id), :resume)
  end

  @doc "Update the agent's instruction overlay."
  @spec update_instructions(String.t(), String.t()) :: :ok
  def update_instructions(agent_id, instructions) do
    GenServer.cast(via(agent_id), {:instructions, instructions})
  end

  @doc "Update arbitrary metadata fields."
  @spec update_metadata(String.t(), map()) :: :ok
  def update_metadata(agent_id, fields) when is_map(fields) do
    GenServer.cast(via(agent_id), {:update_metadata, fields})
  end

  @doc "Check if an agent process is alive by ID."
  @spec alive?(String.t()) :: boolean()
  def alive?(agent_id) do
    case Registry.lookup(@type_iv_registry, agent_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "List all registered agent IDs with metadata."
  @spec list_all() :: [{String.t(), map()}]
  def list_all do
    Registry.select(@type_iv_registry, [{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
  end

  @doc "Lookup a specific agent by ID. Returns {pid, metadata} or nil."
  @spec lookup(String.t()) :: {pid(), map()} | nil
  def lookup(agent_id) do
    case Registry.lookup(@type_iv_registry, agent_id) do
      [{pid, meta}] -> {pid, meta}
      [] -> nil
    end
  end

  @doc "Lookup an agent across all nodes in the cluster. Returns pid or nil."
  @spec lookup_cluster(String.t()) :: pid() | nil
  def lookup_cluster(agent_id) do
    case lookup(agent_id) do
      {pid, _meta} -> pid
      nil -> lookup_remote(agent_id)
    end
  end

  @doc "List all agent PIDs across the cluster via :pg."
  @spec list_cluster() :: [{String.t(), pid()}]
  def list_cluster do
    :pg.which_groups(@pg_scope)
    |> Enum.filter(fn
      {:agent, _id} -> true
      _ -> false
    end)
    |> Enum.flat_map(fn {:agent, id} = group ->
      :pg.get_members(@pg_scope, group)
      |> Enum.map(fn pid -> {id, pid} end)
    end)
  end

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    role = Keyword.get(opts, :role, :worker)
    team = Keyword.get(opts, :team)

    state = %__MODULE__{
      id: id,
      pid: self(),
      role: role,
      team: team,
      backend: Keyword.get(opts, :backend),
      capabilities: Keyword.get(opts, :capabilities, []),
      instructions: Keyword.get(opts, :instructions),
      status: :active,
      spawned_at: DateTime.utc_now(),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    update_registry(id, %{role: role, team: team, status: :active, backend_type: backend_type(state.backend)})

    # Join :pg group for cluster-wide discovery
    :pg.join(@pg_scope, {:agent, id}, self())

    broadcast_lifecycle({:agent_started, id, %{role: role, team: team}})

    Logger.info("[AgentProcess] Started #{id} (role=#{role}, team=#{team || "standalone"})")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_unread, _from, state) do
    {:reply, Enum.reverse(state.unread), %{state | unread: []}}
  end

  def handle_call(:pause, _from, state) do
    update_registry(state.id, %{status: :paused})
    broadcast_lifecycle({:agent_paused, state.id})
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    state.unread |> Enum.reverse() |> Enum.each(&Delivery.deliver(state.backend, &1))
    update_registry(state.id, %{status: :active})
    broadcast_lifecycle({:agent_resumed, state.id})
    {:reply, :ok, %{state | status: :active}}
  end

  @impl true
  def handle_cast({:message, message}, state) do
    msg = Delivery.normalize(message, state.id)
    messages = Enum.take([msg | state.messages], @max_message_buffer)
    Delivery.broadcast(state.id, msg)
    {:noreply, route_message(msg, %{state | messages: messages})}
  end

  def handle_cast({:instructions, instructions}, state) do
    {:noreply, %{state | instructions: instructions}}
  end

  def handle_cast({:update_metadata, fields}, state) do
    {:noreply, %{state | metadata: Map.merge(state.metadata, fields)}}
  end

  @impl true
  def terminate(reason, state) do
    broadcast_lifecycle({:agent_stopped, state.id, reason})
    Logger.info("[AgentProcess] Stopped #{state.id} (reason=#{inspect(reason)})")
    :ok
  end

  # ── Internal ────────────────────────────────────────────────────────

  @spec via(String.t()) :: {:via, module(), tuple()}
  defp via(id), do: {:via, Registry, {@type_iv_registry, id, %{}}}

  @spec lookup_remote(String.t()) :: pid() | nil
  defp lookup_remote(agent_id) do
    case :pg.get_members(@pg_scope, {:agent, agent_id}) do
      [pid | _] -> pid
      [] -> nil
    end
  end

  @spec route_message(map(), t()) :: t()
  defp route_message(msg, %{status: status} = state) when status != :active do
    %{state | unread: [msg | state.unread]}
  end

  defp route_message(msg, %{backend: nil} = state) do
    %{state | unread: [msg | state.unread]}
  end

  defp route_message(msg, state) do
    Delivery.deliver(state.backend, msg)
    state
  end

  @spec update_registry(String.t(), map()) :: :ok
  defp update_registry(id, fields) do
    Registry.update_value(@type_iv_registry, id, fn meta -> Map.merge(meta, fields) end)
  end

  @spec broadcast_lifecycle(tuple()) :: :ok
  defp broadcast_lifecycle(event) do
    Phoenix.PubSub.broadcast(Observatory.PubSub, "fleet:lifecycle", event)
  end

  @spec backend_type(map() | nil) :: atom() | nil
  defp backend_type(nil), do: nil
  defp backend_type(%{type: t}), do: t
  defp backend_type(_), do: :unknown
end
