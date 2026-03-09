defmodule Ichor.Gateway.HITLRelay do
  @moduledoc """
  GenServer managing HITL (Human-In-The-Loop) pause/unpause lifecycle per session.

  When a session is paused, incoming messages are buffered in ETS.
  On unpause, buffered messages are flushed in arrival order via PubSub.
  """

  use GenServer

  alias Ichor.Gateway.HITLEvents.{GateOpenEvent, GateCloseEvent}

  @ets_table :hitl_buffer
  @sweep_interval :timer.minutes(30)
  @abandoned_ttl_seconds 1_800

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

  @doc "Return all buffered messages for a paused session."
  @spec buffered_messages(String.t()) :: [map()]
  def buffered_messages(session_id) do
    :ets.match_object(@ets_table, {{session_id, :_}, :_})
    |> Enum.sort_by(fn {{_sid, ts}, _msg} -> ts end)
    |> Enum.map(fn {{_sid, _ts}, msg} -> msg end)
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

  # --- GenServer callbacks ---

  @impl true
  def init(_opts) do
    :ets.new(@ets_table, [:ordered_set, :public, :named_table])
    schedule_sweep()
    {:ok, %{sessions: %{}, paused_at: %{}}}
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

        Phoenix.PubSub.broadcast(Ichor.PubSub, "session:hitl:#{session_id}", {:hitl, event})

        new_sessions = Map.put(state.sessions, session_id, :paused)
        new_paused_at = Map.put(state.paused_at, session_id, DateTime.utc_now())
        {:reply, :ok, %{state | sessions: new_sessions, paused_at: new_paused_at}}
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

        Phoenix.PubSub.broadcast(Ichor.PubSub, "session:hitl:#{session_id}", {:hitl, event})

        new_sessions = Map.put(state.sessions, session_id, :normal)
        new_paused_at = Map.delete(state.paused_at, session_id)
        {:reply, {:ok, flushed_count}, %{state | sessions: new_sessions, paused_at: new_paused_at}}

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

  def handle_call(:paused_sessions, _from, state) do
    paused = state.sessions |> Enum.filter(fn {_k, v} -> v == :paused end) |> Enum.map(&elem(&1, 0))
    {:reply, paused, state}
  end

  def handle_call({:reject, session_id, agent_id, operator_id}, _from, state) do
    # Delete buffered messages without flushing
    :ets.match_delete(@ets_table, {{session_id, :_}, :_})

    event = %GateCloseEvent{
      session_id: session_id,
      agent_id: agent_id,
      operator_id: operator_id,
      timestamp: DateTime.utc_now(),
      flushed_count: 0
    }

    Phoenix.PubSub.broadcast(Ichor.PubSub, "session:hitl:#{session_id}", {:hitl, event})

    new_sessions = Map.put(state.sessions, session_id, :normal)
    new_paused_at = Map.delete(state.paused_at, session_id)
    {:reply, :ok, %{state | sessions: new_sessions, paused_at: new_paused_at}}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = DateTime.add(DateTime.utc_now(), -@abandoned_ttl_seconds, :second)

    abandoned =
      Enum.filter(state.paused_at, fn {_sid, paused_time} ->
        DateTime.compare(paused_time, cutoff) == :lt
      end)
      |> Enum.map(&elem(&1, 0))

    # Flush and clear abandoned paused sessions
    Enum.each(abandoned, fn sid ->
      flush_buffer(sid)
    end)

    new_sessions = Map.drop(state.sessions, abandoned)
    new_paused_at = Map.drop(state.paused_at, abandoned)

    schedule_sweep()
    {:noreply, %{state | sessions: new_sessions, paused_at: new_paused_at}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Private ---

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp flush_buffer(session_id) do
    messages =
      :ets.match_object(@ets_table, {{session_id, :_}, :_})
      |> Enum.sort_by(fn {{_sid, ts}, _msg} -> ts end)

    Enum.each(messages, fn {{_sid, _ts} = key, msg} ->
      Phoenix.PubSub.broadcast(Ichor.PubSub, "gateway:messages", {:decision_log, msg})
      :ets.delete(@ets_table, key)
    end)

    length(messages)
  end
end
