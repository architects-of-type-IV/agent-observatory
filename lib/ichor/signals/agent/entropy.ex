defmodule Ichor.Signals.Agent.Entropy do
  @moduledoc """
  Loop detection via entropy scoring on a sliding window of tool calls.

  Key: session_id
  Fires: "agent.entropy.loop.detected"
  """

  use Ichor.Signal

  require Logger

  @accepted_topics ["agent.tool.completed", "agent.tool.failed"]

  @impl true
  def name, do: :entropy

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key) do
    %{
      key: key,
      events: [],
      window: [],
      prior_severity: :normal,
      window_size: read_config(:entropy_window_size, 5),
      loop_threshold: read_config(:entropy_loop_threshold, 0.25),
      warning_threshold: read_config(:entropy_warning_threshold, 0.50),
      severity: :normal,
      entropy_score: 1.0
    }
  end

  @impl true
  def handle_event(%Event{} = event, state) do
    tool_name = event.data[:tool_name] || event.data["tool_name"]
    hook_type = event.data[:hook_event_type] || event.data["hook_event_type"]

    case tool_name do
      name when is_binary(name) ->
        window = Enum.take([{name, hook_type} | state.window], state.window_size)
        score = compute_score(window)
        severity = classify(score, state.loop_threshold, state.warning_threshold)

        %{
          state
          | window: window,
            events: [event | state.events],
            entropy_score: score,
            severity: severity
        }

      _ ->
        %{state | events: [event | state.events]}
    end
  end

  @impl true
  def ready?(state, :event), do: state.severity in [:loop, :warning]
  def ready?(_state, _trigger), do: false

  @impl true
  def build_signal(state) do
    Signal.new("agent.entropy.loop.detected", state.key, Enum.reverse(state.events), %{
      entropy_score: state.entropy_score,
      severity: state.severity,
      prior_severity: state.prior_severity
    })
  end

  @impl true
  def reset(state) do
    %{state | events: [], prior_severity: state.severity, severity: :normal, entropy_score: 1.0}
  end

  defp compute_score([]), do: 1.0

  defp compute_score(window) do
    {unique_set, count} =
      Enum.reduce(window, {MapSet.new(), 0}, fn item, {set, n} ->
        {MapSet.put(set, item), n + 1}
      end)

    Float.round(MapSet.size(unique_set) / count, 4)
  end

  defp classify(score, loop_threshold, _warning) when score < loop_threshold, do: :loop
  defp classify(score, _loop, warning_threshold) when score < warning_threshold, do: :warning
  defp classify(_score, _loop, _warning), do: :normal

  defp read_config(key, default) do
    case Application.get_env(:ichor, key, default) do
      value when is_number(value) -> value
      _ -> default
    end
  end
end
