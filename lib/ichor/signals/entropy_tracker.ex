defmodule Ichor.Signals.EntropyTracker do
  @moduledoc """
  Sliding-window entropy tracker for per-session loop detection.

  Maintains a private ETS table of `{intent, tool_call, action_status}` tuples
  per session. On each `record_and_score/2` call, computes a uniqueness ratio
  (unique tuples / window size), classifies severity as `:loop`, `:warning`,
  or `:normal`, and broadcasts topology/alert events as appropriate.

  Thresholds and window size are read from Application config at startup.

  ETS entry format: `{session_id, {window_list, prior_severity, agent_id}}`
  """

  use GenServer

  require Logger

  @type entropy_tuple :: {atom(), atom() | nil, atom() | nil}

  @doc "Start the EntropyTracker GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an entropy tuple and returns the computed score and severity.
  """
  @spec record_and_score(String.t(), entropy_tuple()) ::
          {:ok, float(), :loop | :warning | :normal}
  def record_and_score(session_id, {_intent, _tool_call, _action_status} = tuple) do
    GenServer.call(__MODULE__, {:record_and_score, session_id, tuple})
  end

  @doc """
  Registers an agent_id for a session. Required before LOOP alerts can be emitted.
  """
  @spec register_agent(String.t(), String.t()) :: :ok
  def register_agent(session_id, agent_id) do
    GenServer.cast(__MODULE__, {:register_agent, session_id, agent_id})
  end

  @doc """
  Returns the current window list for a session. Useful for testing.
  """
  @spec get_window(String.t()) :: [entropy_tuple()]
  def get_window(session_id) do
    GenServer.call(__MODULE__, {:get_window, session_id})
  end

  @doc """
  Clears all ETS state. Used by tests to reset between test runs.
  """
  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(:entropy_windows, [:set, :private])
    Ichor.Signals.subscribe(:events)

    {:ok,
     %{
       table: table,
       window_size: read_config(:entropy_window_size, 5),
       loop_threshold: read_config(:entropy_loop_threshold, 0.25),
       warning_threshold: read_config(:entropy_warning_threshold, 0.50)
     }}
  end

  @impl true
  def handle_call({:record_and_score, session_id, tuple}, _from, state) do
    {window, prior, agent_id} = lookup_session(state.table, session_id, nil)
    updated = slide_window(window ++ [tuple], state.window_size)
    score = compute_score(updated)
    severity = classify(score, state.loop_threshold, state.warning_threshold)

    emit_state_change(session_id, severity, prior, score)
    :ets.insert(state.table, {session_id, {updated, severity, agent_id}})

    {:reply, {:ok, score, severity}, state}
  end

  @impl true
  def handle_call(:reset, _from, %{table: table} = state) do
    :ets.delete_all_objects(table)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get_window, session_id}, _from, %{table: table} = state) do
    window =
      case :ets.lookup(table, session_id) do
        [{^session_id, {w, _ps, _aid}}] -> w
        [] -> []
      end

    {:reply, window, state}
  end

  @impl true
  def handle_cast({:register_agent, session_id, agent_id}, %{table: table} = state) do
    case :ets.lookup(table, session_id) do
      [{^session_id, {w, ps, _old_aid}}] ->
        :ets.insert(table, {session_id, {w, ps, agent_id}})

      [] ->
        :ets.insert(table, {session_id, {[], :normal, agent_id}})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        %Ichor.Signals.Message{name: :new_event, data: %{event: event}},
        state
      ) do
    with %{session_id: sid, tool_name: tool, hook_event_type: type}
         when is_binary(sid) and is_binary(tool) <- event do
      {window, prior, agent_id} = lookup_session(state.table, sid, sid)
      updated = slide_window(window ++ [{tool, type}], state.window_size)
      score = compute_score(updated)
      severity = classify(score, state.loop_threshold, state.warning_threshold)

      emit_state_change(sid, severity, prior, score)
      :ets.insert(state.table, {sid, {updated, severity, agent_id}})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp lookup_session(table, session_id, default_agent_id) do
    case :ets.lookup(table, session_id) do
      [{^session_id, {w, ps, aid}}] -> {w, ps, aid}
      [] -> {[], :normal, default_agent_id}
    end
  end

  defp slide_window(window, max_size) when length(window) > max_size, do: tl(window)
  defp slide_window(window, _max_size), do: window

  @spec classify(float(), float(), float()) :: :loop | :warning | :normal
  defp classify(score, loop_threshold, _warning) when score < loop_threshold, do: :loop
  defp classify(score, _loop, warning_threshold) when score < warning_threshold, do: :warning
  defp classify(_score, _loop, _warning), do: :normal

  defp emit_state_change(session_id, :loop, _prior, score) do
    Ichor.Signals.emit(:entropy_alert, %{session_id: session_id, entropy_score: score})
    Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "alert_entropy"})
  end

  defp emit_state_change(session_id, :warning, _prior, _score) do
    Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "blocked"})
  end

  defp emit_state_change(session_id, :normal, prior, _score)
       when prior in [:warning, :loop] do
    Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "active"})
  end

  defp emit_state_change(_session_id, :normal, :normal, _score), do: :ok

  defp compute_score([]), do: 1.0

  defp compute_score(window) do
    unique = window |> MapSet.new() |> MapSet.size()
    Float.round(unique / length(window), 4)
  end

  defp read_config(key, default) do
    case Application.get_env(:ichor, key, default) do
      value when is_number(value) ->
        value

      invalid ->
        Logger.warning(
          "EntropyTracker: invalid #{key} value #{inspect(invalid)}, using default #{inspect(default)}"
        )

        default
    end
  end
end
