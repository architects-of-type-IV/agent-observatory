defmodule Ichor.Fleet.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is pluggable via the Delivery module.
  """

  use GenServer

  alias Ichor.Fleet.AgentProcess.Delivery
  alias Ichor.Gateway.Channels.Tmux

  @max_message_buffer 200
  @type_iv_registry Ichor.Registry
  @pg_scope :ichor_agents
  @liveness_interval :timer.seconds(15)

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

  @doc "Override child_spec for liveness-polled agents (restart: :temporary)."
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

    meta = Keyword.get(opts, :metadata, %{})
    update_registry(id, build_initial_registry_meta(id, state, meta))

    Ichor.Signals.subscribe(:agent_event, id)
    :pg.join(@pg_scope, {:agent, id}, self())
    if Keyword.get(opts, :liveness_poll, false), do: schedule_liveness_check()

    broadcast_lifecycle({:agent_started, id, %{role: role, team: team}})
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

  def handle_cast({:update_fields, fields}, state) do
    update_registry(state.id, fields)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    tmux_target = get_in(state.backend, [:session]) || ""

    if Tmux.available?(tmux_target) do
      schedule_liveness_check()
      {:noreply, state}
    else
      Ichor.Signals.emit(:mes_agent_tmux_gone, %{agent_id: state.id, tmux: tmux_target})
      {:stop, :normal, state}
    end
  end

  def handle_info(%Ichor.Signals.Message{name: :agent_event, data: %{event: event}}, state) do
    fields =
      %{last_event_at: DateTime.utc_now(), status: :active}
      |> maybe_merge(:model, Map.get(event, :model_name))
      |> maybe_merge(:cwd, Map.get(event, :cwd))
      |> maybe_merge(:os_pid, Map.get(event, :os_pid))
      |> merge_current_tool(event)

    update_registry(state.id, fields)
    Ichor.Signals.emit(:fleet_changed, %{agent_id: state.id})
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(:tmux_gone, state) do
    # Tmux window already dead -- skip kill, just clean up BEAM-side registrations.
    # Ichor.Registry auto-deregisters when the process exits -- no explicit remove needed.
    Ichor.EventBuffer.tombstone_session(state.id)
    broadcast_lifecycle({:agent_stopped, state.id, :tmux_gone})
    :ok
  end

  def terminate(reason, state) do
    kill_tmux_backend(state.backend)
    # Ichor.Registry auto-deregisters when the process exits -- no explicit remove needed.
    Ichor.EventBuffer.tombstone_session(state.id)
    broadcast_lifecycle({:agent_stopped, state.id, reason})
    :ok
  end

  # ── Internal ────────────────────────────────────────────────────────

  defp build_initial_registry_meta(id, state, meta) do
    tmux_target = extract_tmux_target(state.backend)
    tmux_session = extract_session_name(tmux_target)
    short_name = meta[:short_name] || meta[:name] || id

    %{
      role: state.role,
      team: state.team,
      status: :active,
      model: meta[:model],
      cwd: meta[:cwd],
      current_tool: nil,
      channels: meta[:channels] || %{tmux: tmux_target, mailbox: id, webhook: nil},
      os_pid: meta[:os_pid],
      last_event_at: meta[:last_event_at] || DateTime.utc_now(),
      short_name: short_name,
      name: meta[:name] || id,
      host: meta[:host] || "local",
      parent_id: meta[:parent_id],
      backend_type: backend_type(state.backend),
      tmux_session: tmux_session,
      tmux_target: tmux_target
    }
  end

  defp extract_tmux_target(%{type: :tmux, session: s}), do: s
  defp extract_tmux_target(_), do: nil

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval)
  end

  defp extract_session_name(nil), do: nil
  defp extract_session_name(target), do: target |> String.split(":") |> hd()

  defp kill_tmux_backend(%{type: :tmux, session: session}) when is_binary(session) do
    if String.contains?(session, ":") do
      Tmux.run_command(["kill-window", "-t", session])
    else
      Tmux.run_command(["kill-session", "-t", session])
    end
  end

  defp kill_tmux_backend(_), do: :ok

  @spec via(String.t()) :: {:via, module(), tuple()}
  defp via(id), do: {:via, Registry, {@type_iv_registry, {:agent, id}, %{}}}

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

  @spec update_registry(String.t(), map()) :: :error | {term(), term()}
  defp update_registry(id, fields) do
    Registry.update_value(@type_iv_registry, {:agent, id}, fn meta -> Map.merge(meta, fields) end)
  end

  @spec broadcast_lifecycle(tuple()) :: :ok
  defp broadcast_lifecycle({:agent_started, id, %{role: role, team: team}}) do
    Ichor.Signals.emit(:agent_started, %{session_id: id, role: role, team: team})
  end

  defp broadcast_lifecycle({:agent_paused, id}) do
    Ichor.Signals.emit(:agent_paused, %{session_id: id})
  end

  defp broadcast_lifecycle({:agent_resumed, id}) do
    Ichor.Signals.emit(:agent_resumed, %{session_id: id})
  end

  defp broadcast_lifecycle({:agent_stopped, id, reason}) do
    Ichor.Signals.emit(:agent_stopped, %{session_id: id, reason: reason})
  end

  @spec backend_type(map() | nil) :: atom() | nil
  defp backend_type(nil), do: nil
  defp backend_type(%{type: t}), do: t
  defp backend_type(_), do: :unknown

  @spec maybe_merge(map(), atom(), any()) :: map()
  defp maybe_merge(map, _key, nil), do: map
  defp maybe_merge(map, key, value), do: Map.put(map, key, value)

  @spec merge_current_tool(map(), map()) :: map()
  defp merge_current_tool(fields, %{hook_event_type: type, tool_name: tool})
       when type in [:PreToolUse, "PreToolUse"] and not is_nil(tool),
       do: Map.put(fields, :current_tool, tool)

  defp merge_current_tool(fields, %{hook_event_type: type})
       when type in [:PostToolUse, :PostToolUseFailure, "PostToolUse", "PostToolUseFailure"],
       do: Map.put(fields, :current_tool, nil)

  defp merge_current_tool(fields, _event), do: fields
end
