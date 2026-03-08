defmodule Observatory.Fleet.AgentProcess do
  @moduledoc """
  A living agent in the fleet. Each agent is a GenServer process with a native
  BEAM mailbox. The process IS the agent -- its PID is the canonical identity,
  its mailbox is the delivery target, its supervision is its lifecycle.

  Backend transport (tmux, SSH, webhook) is pluggable via the Channel behaviour.
  The agent process delegates delivery to its configured backend.
  """

  use GenServer
  require Logger

  @max_message_buffer 200
  @type_iv_registry Observatory.Fleet.ProcessRegistry

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

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  @doc "Send a message to this agent. Non-blocking."
  def send_message(agent_id, message) when is_binary(agent_id) do
    GenServer.cast(via(agent_id), {:message, message})
  end

  @doc "Retrieve the agent's current state."
  def get_state(agent_id) do
    GenServer.call(via(agent_id), :get_state)
  end

  @doc "Retrieve and clear unread messages (for MCP check_inbox compatibility)."
  def get_unread(agent_id) do
    GenServer.call(via(agent_id), :get_unread)
  end

  @doc "Pause the agent (stops backend delivery, buffers messages)."
  def pause(agent_id) do
    GenServer.call(via(agent_id), :pause)
  end

  @doc "Resume a paused agent (delivers buffered messages)."
  def resume(agent_id) do
    GenServer.call(via(agent_id), :resume)
  end

  @doc "Update the agent's instruction overlay."
  def update_instructions(agent_id, instructions) do
    GenServer.cast(via(agent_id), {:instructions, instructions})
  end

  @doc "Update arbitrary metadata fields."
  def update_metadata(agent_id, fields) when is_map(fields) do
    GenServer.cast(via(agent_id), {:update_metadata, fields})
  end

  @doc "Check if an agent process is alive by ID."
  def alive?(agent_id) do
    case Registry.lookup(@type_iv_registry, agent_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc "List all registered agent IDs."
  def list_all do
    Registry.select(@type_iv_registry, [{{:"$1", :_, :"$3"}, [], [{{:"$1", :"$3"}}]}])
  end

  @doc "Lookup a specific agent by ID. Returns {pid, metadata} or nil."
  def lookup(agent_id) do
    case Registry.lookup(@type_iv_registry, agent_id) do
      [{pid, meta}] -> {pid, meta}
      [] -> nil
    end
  end

  # ── Registry ────────────────────────────────────────────────────────

  defp via(id), do: {:via, Registry, {@type_iv_registry, id, %{}}}

  # ── Server Callbacks ────────────────────────────────────────────────

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    role = Keyword.get(opts, :role, :worker)
    team = Keyword.get(opts, :team)
    backend = Keyword.get(opts, :backend)
    capabilities = Keyword.get(opts, :capabilities, [])
    instructions = Keyword.get(opts, :instructions)
    metadata = Keyword.get(opts, :metadata, %{})

    state = %__MODULE__{
      id: id,
      pid: self(),
      role: role,
      team: team,
      backend: backend,
      capabilities: capabilities,
      instructions: instructions,
      status: :active,
      spawned_at: DateTime.utc_now(),
      metadata: metadata,
      messages: [],
      unread: []
    }

    # Update registry metadata so lookups carry useful info
    Registry.update_value(@type_iv_registry, id, fn _ ->
      %{role: role, team: team, status: :active, backend_type: backend_type(backend)}
    end)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "fleet:lifecycle",
      {:agent_started, id, %{role: role, team: team}}
    )

    Logger.info("[AgentProcess] Started #{id} (role=#{role}, team=#{team || "standalone"})")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_unread, _from, state) do
    {:reply, Enum.reverse(state.unread), %{state | unread: []}}
  end

  def handle_call(:pause, _from, state) do
    update_registry_status(state.id, :paused)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "fleet:lifecycle",
      {:agent_paused, state.id}
    )

    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    # Deliver any buffered messages on resume
    Enum.each(Enum.reverse(state.unread), fn msg ->
      deliver_to_backend(state.backend, msg)
    end)

    update_registry_status(state.id, :active)

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "fleet:lifecycle",
      {:agent_resumed, state.id}
    )

    {:reply, :ok, %{state | status: :active}}
  end

  @impl true
  def handle_cast({:message, message}, state) do
    msg = normalize_message(message, state.id)

    # Always buffer in message history
    messages = Enum.take([msg | state.messages], @max_message_buffer)

    # Deliver to backend if active; buffer as unread if paused
    if state.status == :active do
      deliver_to_backend(state.backend, msg)
      broadcast_message(state.id, msg)
      {:noreply, %{state | messages: messages}}
    else
      unread = [msg | state.unread]
      broadcast_message(state.id, msg)
      {:noreply, %{state | messages: messages, unread: unread}}
    end
  end

  def handle_cast({:instructions, instructions}, state) do
    {:noreply, %{state | instructions: instructions}}
  end

  def handle_cast({:update_metadata, fields}, state) do
    {:noreply, %{state | metadata: Map.merge(state.metadata, fields)}}
  end

  @impl true
  def terminate(reason, state) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "fleet:lifecycle",
      {:agent_stopped, state.id, reason}
    )

    Logger.info("[AgentProcess] Stopped #{state.id} (reason=#{inspect(reason)})")
    :ok
  end

  # ── Internal ────────────────────────────────────────────────────────

  defp normalize_message(msg, to) when is_map(msg) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        to: to,
        timestamp: DateTime.utc_now()
      },
      msg
    )
  end

  defp normalize_message(content, to) when is_binary(content) do
    %{
      id: Ecto.UUID.generate(),
      to: to,
      from: "system",
      content: content,
      type: :message,
      timestamp: DateTime.utc_now()
    }
  end

  defp deliver_to_backend(nil, _msg), do: :ok

  defp deliver_to_backend(%{type: :tmux, session: session}, msg) do
    content = msg[:content] || inspect(msg)
    Observatory.Gateway.Channels.Tmux.deliver(session, %{content: content})
  end

  defp deliver_to_backend(%{type: :ssh_tmux} = backend, msg) do
    address = "#{backend.session}@#{backend.host}"
    content = msg[:content] || inspect(msg)
    Observatory.Gateway.Channels.SshTmux.deliver(address, %{content: content})
  end

  defp deliver_to_backend(%{type: :webhook, url: url}, msg) do
    Observatory.Gateway.Channels.WebhookAdapter.deliver(url, msg)
  end

  defp deliver_to_backend(%{type: type}, _msg) do
    Logger.warning("[AgentProcess] Unknown backend type: #{type}")
    :ok
  end

  defp broadcast_message(agent_id, msg) do
    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "messages:stream",
      {:message_delivered, agent_id, msg}
    )
  end

  defp update_registry_status(id, status) do
    Registry.update_value(@type_iv_registry, id, fn meta ->
      Map.put(meta, :status, status)
    end)
  end

  defp backend_type(nil), do: nil
  defp backend_type(%{type: t}), do: t
  defp backend_type(_), do: :unknown
end
