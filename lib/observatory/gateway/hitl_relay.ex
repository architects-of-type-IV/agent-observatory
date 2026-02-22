defmodule Observatory.Gateway.HITLRelay do
  @moduledoc """
  GenServer managing HITL (Human-In-The-Loop) pause/unpause lifecycle per session.

  When a session is paused, incoming messages are buffered in ETS.
  On unpause, buffered messages are flushed in arrival order via PubSub.
  """

  use GenServer

  alias Observatory.Gateway.HITLEvents.{GateOpenEvent, GateCloseEvent}

  @ets_table :hitl_buffer

  # --- Public API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Pause a session. Buffers subsequent messages until unpause."
  @spec pause(String.t(), String.t(), String.t(), String.t()) :: :ok | {:ok, :already_paused}
  def pause(session_id, agent_id, operator_id, reason) do
    GenServer.call(__MODULE__, {:pause, session_id, agent_id, operator_id, reason})
  end

  @doc "Unpause a session. Flushes buffered messages in order."
  @spec unpause(String.t(), String.t(), String.t()) :: {:ok, non_neg_integer()} | {:ok, :not_paused}
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

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@ets_table, [:ordered_set, :public, :named_table])
    {:ok, %{sessions: %{}}}
  end

  @impl true
  def handle_call({:pause, session_id, agent_id, operator_id, reason}, _from, state) do
    case Map.get(state.sessions, session_id) do
      :paused ->
        {:reply, {:ok, :already_paused}, state}

      _ ->
        event = %GateOpenEvent{
          session_id: session_id,
          agent_id: agent_id,
          operator_id: operator_id,
          reason: reason,
          timestamp: DateTime.utc_now()
        }

        Phoenix.PubSub.broadcast(Observatory.PubSub, "session:hitl:#{session_id}", {:hitl, event})

        new_sessions = Map.put(state.sessions, session_id, :paused)
        {:reply, :ok, %{state | sessions: new_sessions}}
    end
  end

  def handle_call({:unpause, session_id, agent_id, operator_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      :paused ->
        flushed_count = flush_buffer(session_id)

        event = %GateCloseEvent{
          session_id: session_id,
          agent_id: agent_id,
          operator_id: operator_id,
          timestamp: DateTime.utc_now(),
          flushed_count: flushed_count
        }

        Phoenix.PubSub.broadcast(Observatory.PubSub, "session:hitl:#{session_id}", {:hitl, event})

        new_sessions = Map.put(state.sessions, session_id, :normal)
        {:reply, {:ok, flushed_count}, %{state | sessions: new_sessions}}

      _ ->
        {:reply, {:ok, :not_paused}, state}
    end
  end

  def handle_call({:rewrite, session_id, trace_id, new_payload}, _from, state) do
    matches =
      :ets.match_object(@ets_table, {{session_id, :_}, :_})

    case Enum.find(matches, fn {_key, msg} -> Map.get(msg, :trace_id) == trace_id end) do
      {key, msg} ->
        updated = Map.put(msg, :payload, new_payload)
        :ets.insert(@ets_table, {key, updated})
        {:reply, :ok, state}

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:inject, session_id, agent_id, payload}, _from, state) do
    key = {session_id, System.monotonic_time()}
    message = %{agent_id: agent_id, payload: payload, injected: true}
    :ets.insert(@ets_table, {key, message})
    {:reply, :ok, state}
  end

  def handle_call({:buffer_message, session_id, message}, _from, state) do
    case Map.get(state.sessions, session_id) do
      :paused ->
        key = {session_id, System.monotonic_time()}
        :ets.insert(@ets_table, {key, message})
        {:reply, :ok, state}

      _ ->
        {:reply, :pass_through, state}
    end
  end

  def handle_call({:session_status, session_id}, _from, state) do
    status = Map.get(state.sessions, session_id, :normal)
    {:reply, status, state}
  end

  # --- Private ---

  defp flush_buffer(session_id) do
    messages =
      :ets.match_object(@ets_table, {{session_id, :_}, :_})
      |> Enum.sort_by(fn {{_sid, ts}, _msg} -> ts end)

    Enum.each(messages, fn {{_sid, _ts} = key, msg} ->
      Phoenix.PubSub.broadcast(Observatory.PubSub, "gateway:messages", {:decision_log, msg})
      :ets.delete(@ets_table, key)
    end)

    length(messages)
  end
end
