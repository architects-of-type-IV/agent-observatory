defmodule Ichor.Projector.EntropyTracker do
  @moduledoc """
  Sliding-window entropy tracker for per-session loop detection.

  Maintains a private ETS table of event tuples per session. Computes a
  uniqueness ratio (unique tuples / window size), classifies severity as
  `:loop`, `:warning`, or `:normal`, and broadcasts topology/alert events.

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
