defmodule Ichor.Fleet.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is handled by `AgentDelivery`.
  Message normalization lives in `AgentMessage`.
  Registry projection logic lives in `AgentRegistryProjection`.
  Backend liveness/termination lives in `AgentBackend`.
  Pure state transitions live in `AgentState`.
  """

  use GenServer

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Fleet.AgentBackend
  alias Ichor.Fleet.AgentDelivery
  alias Ichor.Fleet.AgentRegistryProjection
  alias Ichor.Fleet.AgentState

  @type_iv_registry Ichor.Registry
  @pg_scope :ichor_agents
  @liveness_interval :timer.seconds(15)

  @type status :: :initializing | :active | :paused | :terminating

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          pid: pid() | nil,
          role: atom(),
          team: String.t() | nil,
          backend: map() | nil,
          capabilities: [atom()],
          instructions: String.t() | nil,
          status: status(),
          spawned_at: DateTime.t() | nil,
          metadata: map(),
          message_log: [map()],
          inbox: [map()],
          pending_delivery: [map()]
        }

  @enforce_keys [:id, :role, :status]
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
    name: "",
    metadata: %{},
    message_log: [],
    inbox: [],
    pending_delivery: []
  ]

  @doc "Start an agent process and register it in the fleet registry."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc "Override child_spec for liveness-polled agents (restart: :temporary)."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    spec = super(opts)

    if Keyword.get(opts, :liveness_poll, false) do
      Map.put(spec, :restart, :temporary)
    else
      spec
    end
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

  @doc "Update arbitrary metadata fields on the GenServer state."
  @spec update_metadata(String.t(), map()) :: :ok
  def update_metadata(agent_id, fields) when is_map(fields) do
    GenServer.cast(via(agent_id), {:update_metadata, fields})
  end

  @doc "Update arbitrary metadata fields directly on the Registry entry."
  @spec update_fields(String.t(), map()) :: :ok
  def update_fields(agent_id, fields) when is_map(fields) do
    GenServer.cast(via(agent_id), {:update_fields, fields})
  end

  @doc "Check if an agent process is alive by ID."
  @spec alive?(String.t()) :: boolean()
  def alive?(agent_id) do
    case Registry.lookup(@type_iv_registry, {:agent, agent_id}) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "List all registered agent IDs with metadata."
  @spec list_all() :: [{String.t(), map()}]
  def list_all do
    Registry.select(@type_iv_registry, [
      {{{:agent, :"$1"}, :_, :"$3"}, [], [{{:"$1", :"$3"}}]}
    ])
  end

  @doc "Lookup a specific agent by ID. Returns {pid, metadata} or nil."
  @spec lookup(String.t()) :: {pid(), map()} | nil
  def lookup(agent_id) do
    case Registry.lookup(@type_iv_registry, {:agent, agent_id}) do
      [{pid, meta}] -> {pid, meta}
      [] -> nil
    end
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.get(opts, :name, "")
    role = Keyword.get(opts, :role, :worker)
    team = Keyword.get(opts, :team)
    meta = Keyword.get(opts, :metadata, %{})

    state = %__MODULE__{
      id: id,
      name: name,
      pid: self(),
      role: role,
      team: team,
      backend: Keyword.get(opts, :backend),
      capabilities: Keyword.get(opts, :capabilities, []),
      instructions: Keyword.get(opts, :instructions),
      status: :active,
      spawned_at: DateTime.utc_now(),
      metadata: meta
    }

    case AgentRegistryProjection.update(
           id,
           AgentRegistryProjection.build_initial(id, state, meta)
         ) do
      {:error, :not_registered} ->
        Logger.warning("[AgentProcess] registry update on init failed: #{id} not registered")

      _ ->
        :ok
    end

    Ichor.Events.subscribe_key(id)
    :pg.join(@pg_scope, {:agent, id}, self())
    if Keyword.get(opts, :liveness_poll, false), do: schedule_liveness_check()

    Events.emit(
      Event.new(
        "fleet.agent.started",
        id,
        %{session_id: id, name: name, role: role, team: team}
      )
    )

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_unread, _from, state) do
    {messages, new_state} = AgentState.pop_inbox(state)
    {:reply, messages, new_state}
  end

  def handle_call(:pause, _from, state) do
    case AgentRegistryProjection.update(state.id, %{status: :paused}) do
      {:error, :not_registered} ->
        Logger.warning(
          "[AgentProcess] registry update on pause failed: #{state.id} not registered"
        )

      _ ->
        :ok
    end

    Events.emit(
      Event.new("fleet.agent.paused", state.id, %{session_id: state.id, name: state.name})
    )

    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    case AgentRegistryProjection.update(state.id, %{status: :active}) do
      {:error, :not_registered} ->
        Logger.warning(
          "[AgentProcess] registry update on resume failed: #{state.id} not registered"
        )

      _ ->
        :ok
    end

    Events.emit(
      Event.new("fleet.agent.resumed", state.id, %{session_id: state.id, name: state.name})
    )

    {pending, new_state} = AgentState.drain_pending(state)
    new_state = %{new_state | status: :active}
    async_deliver_many(new_state.backend, pending)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:message, message}, %{status: :active} = state) do
    {msg, new_state} = AgentState.record_message(state, message)
    async_deliver(new_state.backend, msg)
    {:noreply, new_state}
  end

  def handle_cast({:message, message}, state) do
    {_msg, new_state} = AgentState.record_message(state, message)
    {:noreply, new_state}
  end

  def handle_cast({:instructions, instructions}, state) do
    {:noreply, %{state | instructions: instructions}}
  end

  def handle_cast({:update_metadata, fields}, state) do
    {:noreply, %{state | metadata: Map.merge(state.metadata, fields)}}
  end

  def handle_cast({:update_fields, fields}, state) do
    case AgentRegistryProjection.update(state.id, fields) do
      {:error, :not_registered} ->
        Logger.warning("[AgentProcess] registry update_fields failed: #{state.id} not registered")

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    me = self()
    backend = state.backend

    Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
      send(me, {:liveness_result, AgentBackend.tmux_alive?(backend)})
    end)

    {:noreply, state}
  end

  def handle_info({:liveness_result, {true, _tmux_target}}, state) do
    schedule_liveness_check()
    {:noreply, state}
  end

  def handle_info({:liveness_result, {false, tmux_target}}, state) do
    Events.emit(
      Event.new(
        "fleet.agent.tmux_gone",
        state.id,
        %{agent_id: state.id, name: state.name, tmux: tmux_target}
      )
    )

    {:stop, :normal, %{state | status: :terminating}}
  end

  def handle_info(%Ichor.Events.Event{topic: "agent.event", data: %{event: event}}, state) do
    case AgentRegistryProjection.update(
           state.id,
           AgentRegistryProjection.fields_from_event(event)
         ) do
      {:error, :not_registered} ->
        Logger.warning(
          "[AgentProcess] registry update on agent_event failed: #{state.id} not registered"
        )

      _ ->
        :ok
    end

    Events.emit(Event.new("fleet.registry.changed", state.id, %{agent_id: state.id}))

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Ichor.Registry auto-deregisters when the process exits -- no explicit remove needed.
  # EventStream subscribes to :agent_stopped and tombstones the session itself.

  @impl true
  def terminate(:normal, %{status: :terminating} = state) do
    Events.emit(
      Event.new(
        "fleet.agent.stopped",
        state.id,
        %{session_id: state.id, name: state.name, reason: :tmux_gone}
      )
    )

    :ok
  end

  def terminate(reason, state) do
    AgentBackend.terminate(state.backend)

    Events.emit(
      Event.new(
        "fleet.agent.stopped",
        state.id,
        %{session_id: state.id, name: state.name, reason: reason}
      )
    )

    :ok
  end

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval)
  end

  defp async_deliver(backend, msg) do
    Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
      AgentDelivery.deliver(backend, msg)
    end)
  end

  defp async_deliver_many(backend, messages) do
    Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
      AgentDelivery.deliver_many(backend, messages)
    end)
  end

  @spec via(String.t()) :: {:via, module(), tuple()}
  defp via(id), do: {:via, Registry, {@type_iv_registry, {:agent, id}, %{}}}
end
