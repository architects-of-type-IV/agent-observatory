defmodule Observatory.Gateway.EntropyTracker do
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

  # -- Public API --

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

  # -- GenServer Callbacks --

  @impl true
  def init(_opts) do
    table = :ets.new(:entropy_windows, [:set, :private])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:record_and_score, session_id, tuple}, _from, %{table: table} = state) do
    # Read config on every call (FR-9.11)
    window_size = read_config(:entropy_window_size, 5)
    loop_threshold = read_config(:entropy_loop_threshold, 0.25)
    warning_threshold = read_config(:entropy_warning_threshold, 0.50)

    # Read existing entry or initialize
    {window, prior_severity, agent_id} =
      case :ets.lookup(table, session_id) do
        [{^session_id, {w, ps, aid}}] -> {w, ps, aid}
        [] -> {[], :normal, nil}
      end

    # Append tuple, evict oldest if over window_size
    updated_window = window ++ [tuple]

    updated_window =
      if length(updated_window) > window_size do
        List.delete_at(updated_window, 0)
      else
        updated_window
      end

    # Compute score
    score = compute_score(updated_window)

    # Classify severity
    {severity, reply} =
      cond do
        score < loop_threshold ->
          # LOOP: broadcast alert + topology
          case build_alert_event(session_id, agent_id, score, updated_window) do
            {:error, :missing_agent_id} = err ->
              # Still update window and severity, but return error
              :ets.insert(table, {session_id, {updated_window, :loop, agent_id}})
              {:loop, err}

            :ok ->
              Phoenix.PubSub.broadcast(
                Observatory.PubSub,
                "gateway:topology",
                %{session_id: session_id, state: "alert_entropy"}
              )

              :ets.insert(table, {session_id, {updated_window, :loop, agent_id}})
              {:loop, {:ok, score, :loop}}
          end

        score < warning_threshold ->
          # WARNING: topology only, no alert
          Phoenix.PubSub.broadcast(
            Observatory.PubSub,
            "gateway:topology",
            %{session_id: session_id, state: "blocked"}
          )

          :ets.insert(table, {session_id, {updated_window, :warning, agent_id}})
          {:warning, {:ok, score, :warning}}

        true ->
          # NORMAL: reset topology if recovering
          if prior_severity in [:warning, :loop] do
            Phoenix.PubSub.broadcast(
              Observatory.PubSub,
              "gateway:topology",
              %{session_id: session_id, state: "active"}
            )
          end

          :ets.insert(table, {session_id, {updated_window, :normal, agent_id}})
          {:normal, {:ok, score, :normal}}
      end

    _ = severity
    {:reply, reply, state}
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

  # -- Private Functions --

  defp compute_score([]), do: 1.0

  defp compute_score(window) do
    n = length(window)
    unique = window |> MapSet.new() |> MapSet.size()
    Float.round(unique / n, 4)
  end

  defp build_alert_event(session_id, nil, _score, _window) do
    Logger.warning(
      "EntropyTracker: cannot emit alert, missing agent_id for session #{session_id}"
    )

    {:error, :missing_agent_id}
  end

  defp build_alert_event(session_id, agent_id, score, window) do
    frequencies = Enum.frequencies(window)
    {pattern, count} = Enum.max_by(frequencies, fn {_k, v} -> v end)

    event = %{
      event_type: "entropy_alert",
      session_id: session_id,
      agent_id: agent_id,
      entropy_score: score,
      window_size: length(window),
      repeated_pattern: %{
        intent: to_string(elem(pattern, 0)),
        tool_call: to_string(elem(pattern, 1)),
        action_status: to_string(elem(pattern, 2))
      },
      occurrence_count: count
    }

    Phoenix.PubSub.broadcast(
      Observatory.PubSub,
      "gateway:entropy_alerts",
      event
    )

    :ok
  end

  defp read_config(key, default) do
    value = Application.get_env(:observatory, key, default)

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
