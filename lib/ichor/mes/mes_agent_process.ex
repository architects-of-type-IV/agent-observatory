defmodule Ichor.Mes.MesAgentProcess do
  @moduledoc """
  GenServer for a single MES agent. Owns the BEAM identity for one tmux window
  in an MES manufacturing run.

  Key difference from Fleet.AgentProcess: the tmux window is the source of truth.
  This process monitors the window and self-terminates when it dies. It does NOT
  kill the tmux window on terminate -- tmux owns the agent's Claude process.

  Registers in Fleet.ProcessRegistry so the dashboard and messaging pipeline
  see MES agents as first-class fleet members.
  """

  use GenServer, restart: :temporary

  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Signals

  @type_iv_registry Ichor.Fleet.ProcessRegistry
  @pg_scope :ichor_agents
  @liveness_interval :timer.seconds(15)
  @max_message_buffer 200

  defstruct [
    :id,
    :role,
    :team,
    :tmux_target,
    :run_id,
    :cwd,
    messages: [],
    unread: []
  ]

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via(id))
  end

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    role = Keyword.get(opts, :role, :worker)
    team = Keyword.get(opts, :team)
    tmux_target = Keyword.fetch!(opts, :tmux_target)
    run_id = Keyword.get(opts, :run_id)
    cwd = Keyword.get(opts, :cwd)

    state = %__MODULE__{
      id: id,
      role: role,
      team: team,
      tmux_target: tmux_target,
      run_id: run_id,
      cwd: cwd
    }

    # Register in fleet-wide ProcessRegistry for dashboard + messaging visibility
    Registry.update_value(@type_iv_registry, id, fn _ ->
      %{
        role: role,
        team: team,
        status: :active,
        backend_type: :tmux,
        cwd: cwd,
        tmux_session: tmux_target,
        model: "sonnet"
      }
    end)

    :pg.join(@pg_scope, {:agent, id}, self())

    schedule_liveness_check()
    Signals.emit(:mes_agent_registered, %{agent_id: id, team: team, tmux: tmux_target})

    {:ok, state}
  end

  @impl true
  def handle_call(:get_unread, _from, state) do
    {:reply, Enum.reverse(state.unread), %{state | unread: []}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:message, message}, state) do
    msg = normalize_message(message, state.id)
    messages = Enum.take([msg | state.messages], @max_message_buffer)

    # Deliver to tmux window
    if Tmux.available?(state.tmux_target) do
      Tmux.deliver(state.tmux_target, msg)
    end

    # Broadcast for dashboard
    Ichor.Signals.emit(:message_delivered, state.id, %{message: msg})

    {:noreply, %{state | messages: messages, unread: [msg | state.unread]}}
  end

  def handle_cast({:update_metadata, _fields}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_liveness, state) do
    if tmux_alive?(state.tmux_target) do
      schedule_liveness_check()
      {:noreply, state}
    else
      Signals.emit(:mes_agent_tmux_gone, %{agent_id: state.id, tmux: state.tmux_target})
      {:stop, :normal, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Do NOT kill tmux -- tmux is the source of truth, not BEAM.
    # Just clean up BEAM-side registrations.
    Ichor.EventBuffer.tombstone_session(state.id)
    Signals.emit(:mes_agent_stopped, %{agent_id: state.id})
    :ok
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp via(id), do: {:via, Registry, {@type_iv_registry, id, %{}}}

  defp schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval)
  end

  defp tmux_alive?(tmux_target) do
    Tmux.available?(tmux_target)
  end

  defp normalize_message(msg, _to_id) when is_map(msg), do: msg

  defp normalize_message(content, to_id) when is_binary(content) do
    %{
      content: content,
      from: "operator",
      to: to_id,
      timestamp: DateTime.utc_now()
    }
  end
end
