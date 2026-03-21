defmodule Ichor.Infrastructure.HITLRelay do
  @moduledoc """
  GenServer managing HITL (Human-In-The-Loop) pause/unpause lifecycle per session.

  When a session is paused, incoming messages are buffered in ETS via
  `HITL.Buffer`.  On unpause, buffered messages are flushed in arrival order
  via PubSub.  Session pause/resume state is managed by `HITL.SessionState`.
  Signal emission is delegated to `HITL.Events`.
  """

  use GenServer

  alias Ichor.Infrastructure.HITL.Buffer
  alias Ichor.Infrastructure.HITL.Events
  alias Ichor.Infrastructure.HITL.SessionState

  @sweep_interval :timer.minutes(30)
  @abandoned_ttl_seconds 1_800

  @doc "Start the HITLRelay GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Pause a session. Buffers subsequent messages until unpause."
  @spec pause(String.t(), String.t(), String.t(), String.t()) :: :ok | {:ok, :already_paused}
  def pause(session_id, agent_id, operator_id, reason) do
    GenServer.call(__MODULE__, {:pause, session_id, agent_id, operator_id, reason})
  end

  @doc "Unpause a session. Flushes buffered messages in order."
  @spec unpause(String.t(), String.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:ok, :not_paused}
  def unpause(session_id, agent_id, operator_id) do
    GenServer.call(__MODULE__, {:unpause, session_id, agent_id, operator_id})
  end

  @doc "Rewrite a buffered message's payload by trace_id."
  @spec rewrite(String.t(), String.t(), map()) :: :ok | {:error, :not_found}
  def rewrite(session_id, trace_id, new_payload) do
    GenServer.call(__MODULE__, {:rewrite, session_id, trace_id, new_payload})
  end

  @doc "Inject a new message into the buffer for a paused session."
  @spec inject(String.t(), String.t(), map()) :: :ok
  def inject(session_id, agent_id, payload) do
    GenServer.call(__MODULE__, {:inject, session_id, agent_id, payload})
  end

  @doc "Buffer a message if the session is paused, or pass through if normal."
  @spec buffer_message(String.t(), map()) :: :ok | :pass_through
  def buffer_message(session_id, message) do
    GenServer.call(__MODULE__, {:buffer_message, session_id, message})
  end

  @doc "Return the current status of a session (:paused or :normal)."
  @spec session_status(String.t()) :: :paused | :normal
  def session_status(session_id) do
    GenServer.call(__MODULE__, {:session_status, session_id})
  end

  @doc "Return all buffered messages for a paused session."
  @spec buffered_messages(String.t()) :: [map()]
  def buffered_messages(session_id) do
    Buffer.fetch(session_id) |> Enum.map(fn {_key, msg} -> msg end)
  end

  @doc "Return all currently paused session IDs."
  @spec paused_sessions() :: [String.t()]
  def paused_sessions do
    GenServer.call(__MODULE__, :paused_sessions)
  end

  @doc "Discard all buffered messages for a session and unpause."
  @spec reject(String.t(), String.t(), String.t()) :: :ok
  def reject(session_id, agent_id, operator_id) do
    GenServer.call(__MODULE__, {:reject, session_id, agent_id, operator_id})
  end

  @impl true
  def init(_opts) do
    Buffer.create_table()
    schedule_sweep()
    {:ok, SessionState.new()}
  end

  @impl true
  def handle_call({:pause, session_id, _agent_id, _operator_id, _reason}, _from, state) do
    case SessionState.paused?(state, session_id) do
      true ->
        {:reply, {:ok, :already_paused}, state}

      false ->
        Events.gate_open(session_id)
        {:reply, :ok, SessionState.pause(state, session_id)}
    end
  end

  def handle_call({:unpause, session_id, _agent_id, _operator_id}, _from, state) do
    case SessionState.paused?(state, session_id) do
      true ->
        flushed_count = flush_buffer(session_id)
        Events.gate_close(session_id)
        {:reply, {:ok, flushed_count}, SessionState.resume(state, session_id)}

      false ->
        {:reply, {:ok, :not_paused}, state}
    end
  end

  def handle_call({:rewrite, session_id, trace_id, new_payload}, _from, state) do
    {:reply, Buffer.rewrite(session_id, trace_id, new_payload), state}
  end

  def handle_call({:inject, session_id, agent_id, payload}, _from, state) do
    Buffer.insert(session_id, %{agent_id: agent_id, payload: payload, injected: true})
    {:reply, :ok, state}
  end

  def handle_call({:buffer_message, session_id, message}, _from, state) do
    case SessionState.paused?(state, session_id) do
      true ->
        Buffer.insert(session_id, message)
        {:reply, :ok, state}

      false ->
        {:reply, :pass_through, state}
    end
  end

  def handle_call({:session_status, session_id}, _from, state) do
    {:reply, SessionState.status(state, session_id), state}
  end

  def handle_call(:paused_sessions, _from, state) do
    {:reply, SessionState.paused_session_ids(state), state}
  end

  def handle_call({:reject, session_id, _agent_id, _operator_id}, _from, state) do
    Buffer.discard(session_id)
    Events.gate_close(session_id)
    {:reply, :ok, SessionState.resume(state, session_id)}
  end

  @impl true
  def handle_info(:sweep, state) do
    abandoned = SessionState.abandoned_since(state, @abandoned_ttl_seconds)

    Enum.each(abandoned, fn sid ->
      flush_buffer(sid)
      Events.auto_released(sid)
    end)

    schedule_sweep()
    {:noreply, SessionState.drop(state, abandoned)}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp flush_buffer(session_id) do
    entries = Buffer.fetch(session_id)

    Enum.each(entries, fn {key, msg} ->
      Events.decision_log(msg)
      Buffer.delete(key)
    end)

    length(entries)
  end
end
