defmodule Ichor.Control.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is pluggable via the Delivery module.
  """

  use GenServer

  alias Ichor.Control.AgentProcess.Lifecycle
  alias Ichor.Control.AgentProcess.Mailbox
  alias Ichor.Control.AgentProcess.Registry, as: AgentRegistry
  @type_iv_registry Ichor.Registry
  @pg_scope :ichor_agents

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
    metadata: %{},
    messages: [],
    unread: []
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

    meta = Keyword.get(opts, :metadata, %{})
    AgentRegistry.update(id, AgentRegistry.build_initial_meta(id, state, meta))

    Ichor.Signals.subscribe(:agent_event, id)
    :pg.join(@pg_scope, {:agent, id}, self())
    if Keyword.get(opts, :liveness_poll, false), do: Lifecycle.schedule_liveness_check()

    Lifecycle.broadcast({:agent_started, id, %{role: role, team: team}})
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  def handle_call(:get_unread, _from, state) do
    {:reply, Enum.reverse(state.unread), %{state | unread: []}}
  end

  def handle_call(:pause, _from, state) do
    AgentRegistry.update(state.id, %{status: :paused})
    Lifecycle.broadcast({:agent_paused, state.id})
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    AgentRegistry.update(state.id, %{status: :active})
    Lifecycle.broadcast({:agent_resumed, state.id})
    {:reply, :ok, Mailbox.deliver_unread(state)}
  end

  @impl true
  def handle_cast({:message, message}, state) do
    {:noreply, Mailbox.apply_incoming_message(state, message)}
  end

  def handle_cast({:instructions, instructions}, state) do
    {:noreply, %{state | instructions: instructions}}
  end

  def handle_cast({:update_metadata, fields}, state) do
    {:noreply, %{state | metadata: Map.merge(state.metadata, fields)}}
  end

  def handle_cast({:update_fields, fields}, state) do
    AgentRegistry.update(state.id, fields)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    {alive?, tmux_target} = Lifecycle.tmux_alive?(state.backend)

    if alive? do
      Lifecycle.schedule_liveness_check()
      {:noreply, state}
    else
      Ichor.Signals.emit(:mes_agent_tmux_gone, %{agent_id: state.id, tmux: tmux_target})
      {:stop, :normal, state}
    end
  end

  def handle_info(%Ichor.Signals.Message{name: :agent_event, data: %{event: event}}, state) do
    AgentRegistry.update(state.id, AgentRegistry.fields_from_event(event))
    Ichor.Signals.emit(:fleet_changed, %{agent_id: state.id})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(:tmux_gone, state) do
    # Tmux window already dead -- skip kill, just clean up BEAM-side registrations.
    # Ichor.Registry auto-deregisters when the process exits -- no explicit remove needed.
    Ichor.EventBuffer.tombstone_session(state.id)
    Lifecycle.broadcast({:agent_stopped, state.id, :tmux_gone})
    :ok
  end

  def terminate(reason, state) do
    Lifecycle.terminate_backend(state.backend)
    # Ichor.Registry auto-deregisters when the process exits -- no explicit remove needed.
    Ichor.EventBuffer.tombstone_session(state.id)
    Lifecycle.broadcast({:agent_stopped, state.id, reason})
    :ok
  end

  @spec via(String.t()) :: {:via, module(), tuple()}
  defp via(id), do: {:via, Registry, {@type_iv_registry, {:agent, id}, %{}}}
end
