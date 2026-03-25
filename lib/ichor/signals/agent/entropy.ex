defmodule Ichor.Signals.Agent.Entropy do
  @moduledoc """
  Signal accumulator for per-session loop detection via entropy scoring.

  Watches `agent.tool.completed` and `agent.tool.failed` events for a session.
  Maintains a sliding window of `{tool_name, hook_event_type}` tuples, computes
  a uniqueness ratio (unique tuples / window size), and fires when the score
  crosses the configured loop threshold.

  Key: session_id (string, from event.key)

  Fires: `"agent.entropy.loop.detected"` with `entropy_score` and `severity`
  in metadata. The ActionHandler re-emits old-style PubSub signals for backward
  compatibility with the dashboard.

  Thresholds and window size are read from Application config:
  - `:entropy_window_size`     (default 5)
  - `:entropy_loop_threshold`  (default 0.25)
  - `:entropy_warning_threshold` (default 0.50)
  """

  use Ichor.Signal

  require Logger

  @type severity :: :loop | :warning | :normal
  @type entropy_tuple :: {String.t(), String.t() | nil}

  @impl true
  @spec topics() :: [String.t()]
  def topics, do: ["agent.tool.completed", "agent.tool.failed"]

  @impl true
  @spec signal_name() :: String.t()
  def signal_name, do: "agent.entropy.loop.detected"

  @impl true
  @spec init_state(term()) :: map()
  def init_state(key) do
    %{
      key: key,
      events: [],
      window: [],
      prior_severity: :normal,
      window_size: read_config(:entropy_window_size, 5),
      loop_threshold: read_config(:entropy_loop_threshold, 0.25),
      warning_threshold: read_config(:entropy_warning_threshold, 0.50),
      metadata: %{}
    }
  end

  @impl true
  @spec handle_event(map(), Ichor.Events.Event.t()) :: map()
  def handle_event(state, event) do
    tool_name = get_in(event.data, [:tool_name]) || get_in(event.data, ["tool_name"])
    hook_type = get_in(event.data, [:hook_event_type]) || get_in(event.data, ["hook_event_type"])

    case tool_name do
      name when is_binary(name) ->
        updated_window = slide_window([{name, hook_type} | state.window], state.window_size)
        score = compute_score(updated_window)
        severity = classify(score, state.loop_threshold, state.warning_threshold)

        %{
          state
          | window: updated_window,
            events: [event | state.events],
            metadata: %{
              entropy_score: score,
              severity: severity,
              prior_severity: state.prior_severity
            }
        }

      _ ->
        %{state | events: [event | state.events]}
    end
  end

  @impl true
  @spec ready?(map(), :event | :timer) :: boolean()
  def ready?(state, :event) do
    Map.get(state.metadata, :severity) in [:loop, :warning]
  end

  def ready?(_state, :timer), do: false

  @impl true
  @spec build_signal(map()) :: Ichor.Signals.Signal.t()
  def build_signal(state) do
    score = get_in(state, [:metadata, :entropy_score]) || 1.0
    severity = get_in(state, [:metadata, :severity]) || :normal
    prior = get_in(state, [:metadata, :prior_severity]) || :normal

    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      Enum.reverse(state.events),
      %{entropy_score: score, severity: severity, prior_severity: prior}
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    require Logger
    score = signal.metadata[:entropy_score]
    severity = signal.metadata[:severity]

    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} score=#{score} severity=#{severity}"
    )

    case severity do
      :loop ->
        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.entropy.alert", signal.key, %{
            session_id: signal.key,
            entropy_score: score
          })
        )

        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
            agent_id: signal.key,
            state: "alert_entropy"
          })
        )

      :warning ->
        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
            agent_id: signal.key,
            state: "blocked"
          })
        )

      :normal ->
        if signal.metadata[:prior_severity] in [:warning, :loop] do
          Ichor.Events.emit(
            Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
              agent_id: signal.key,
              state: "active"
            })
          )
        end
    end

    :ok
  end

  @impl true
  @spec reset(map()) :: map()
  def reset(state) do
    current_severity = get_in(state, [:metadata, :severity]) || :normal

    %{
      state
      | events: [],
        prior_severity: current_severity,
        metadata: %{}
    }
  end

  # Scoring logic -- preserved exactly from EntropyTracker

  @spec slide_window([entropy_tuple()], pos_integer()) :: [entropy_tuple()]
  defp slide_window(window, max_size) do
    Enum.take(window, max_size)
  end

  @spec compute_score([entropy_tuple()]) :: float()
  defp compute_score([]), do: 1.0

  defp compute_score(window) do
    {unique_set, count} =
      Enum.reduce(window, {MapSet.new(), 0}, fn item, {set, n} ->
        {MapSet.put(set, item), n + 1}
      end)

    Float.round(MapSet.size(unique_set) / count, 4)
  end

  @spec classify(float(), float(), float()) :: severity()
  defp classify(score, loop_threshold, _warning) when score < loop_threshold, do: :loop
  defp classify(score, _loop, warning_threshold) when score < warning_threshold, do: :warning
  defp classify(_score, _loop, _warning), do: :normal

  @spec read_config(atom(), number()) :: number()
  defp read_config(key, default) do
    case Application.get_env(:ichor, key, default) do
      value when is_number(value) ->
        value

      invalid ->
        Logger.warning(
          "Entropy signal: invalid #{key} value #{inspect(invalid)}, using default #{inspect(default)}"
        )

        default
    end
  end
end
