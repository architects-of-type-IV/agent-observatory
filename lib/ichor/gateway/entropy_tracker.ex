defmodule Ichor.Gateway.EntropyTracker do
  @moduledoc """
  Sliding-window entropy tracker for per-session loop detection.

  Maintains a private ETS table of `{intent, tool_call, action_status}` tuples
  per session. On each `record_and_score/2` call, computes a uniqueness ratio
  (unique tuples / window size), classifies severity as `:loop`, `:warning`,
  or `:normal`, and broadcasts topology/alert events as appropriate.

  All thresholds and window size are read from Application config on every call
  (not cached at startup) so runtime changes take effect immediately.

  ETS entry format: `{session_id, {window_list, prior_severity, agent_id}}`
  """

  use GenServer

  require Logger

  @doc "Start the EntropyTracker GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an entropy tuple and returns the computed score and severity.

  Returns `{:ok, score, severity}` or `{:error, :missing_agent_id}` when a
  LOOP alert cannot be emitted due to missing agent registration.
  """
  @spec record_and_score(String.t(), {term(), term(), term()}) ::
          {:ok, float(), :loop | :warning | :normal} | {:error, :missing_agent_id}
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
  @spec get_window(String.t()) :: list()
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
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:record_and_score, session_id, tuple}, _from, %{table: table} = state) do
    window_size = read_config(:entropy_window_size, 5)
    loop_threshold = read_config(:entropy_loop_threshold, 0.25)
    warning_threshold = read_config(:entropy_warning_threshold, 0.50)

    {window, prior_severity, agent_id} =
      case :ets.lookup(table, session_id) do
        [{^session_id, {w, ps, aid}}] -> {w, ps, aid}
        [] -> {[], :normal, nil}
      end

    updated_window = slide_window(window ++ [tuple], window_size)
    score = compute_score(updated_window)

    reply =
      classify_and_store(
        table,
        session_id,
        agent_id,
        prior_severity,
        updated_window,
        score,
        loop_threshold,
        warning_threshold
      )

    {:reply, reply, state}
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

  defp slide_window(window, max_size) when length(window) > max_size do
    List.delete_at(window, 0)
  end

  defp slide_window(window, _max_size), do: window

  defp classify_and_store(
         table,
         session_id,
         agent_id,
         _prior_severity,
         window,
         score,
         loop_threshold,
         _warning_threshold
       )
       when score < loop_threshold do
    build_alert_event(session_id, agent_id, score, window)
    Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "alert_entropy"})
    :ets.insert(table, {session_id, {window, :loop, agent_id}})
    {:ok, score, :loop}
  end

  defp classify_and_store(
         table,
         session_id,
         agent_id,
         _prior_severity,
         window,
         score,
         _loop_threshold,
         warning_threshold
       )
       when score < warning_threshold do
    Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "blocked"})
    :ets.insert(table, {session_id, {window, :warning, agent_id}})
    {:ok, score, :warning}
  end

  defp classify_and_store(
         table,
         session_id,
         agent_id,
         prior_severity,
         window,
         score,
         _loop_threshold,
         _warning_threshold
       ) do
    if prior_severity in [:warning, :loop] do
      Ichor.Signals.emit(:node_state_update, %{agent_id: session_id, state: "active"})
    end

    :ets.insert(table, {session_id, {window, :normal, agent_id}})
    {:ok, score, :normal}
  end

  defp compute_score([]), do: 1.0

  defp compute_score(window) do
    n = length(window)
    unique = window |> MapSet.new() |> MapSet.size()
    Float.round(unique / n, 4)
  end

  defp build_alert_event(session_id, _agent_id, score, _window) do
    Ichor.Signals.emit(:entropy_alert, %{
      session_id: session_id,
      entropy_score: score
    })

    :ok
  end

  defp read_config(key, default) do
    value = Application.get_env(:ichor, key, default)

    if is_number(value) do
      value
    else
      Logger.warning(
        "EntropyTracker: invalid #{key} value #{inspect(value)}, using default #{inspect(default)}"
      )

      default
    end
  end
end
