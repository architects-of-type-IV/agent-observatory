defmodule Ichor.Signals.Agent.Unresponsive do
  @moduledoc """
  Fires when an agent has received nudges without recovering.

  Watches `agent.nudge.*` events keyed by session_id. Accumulates
  nudge escalations and fires when the count crosses the threshold,
  indicating the agent is truly unresponsive and needs intervention.

  Key: session_id
  """

  use Ichor.Signal

  @accepted_prefixes ["agent.nudge."]
  @nudge_threshold 3

  @impl true
  def name, do: :unresponsive

  @impl true
  def accepts?(%Event{topic: topic}) do
    Enum.any?(@accepted_prefixes, &String.starts_with?(topic, &1))
  end

  @impl true
  def init(key), do: %{key: key, events: [], nudge_count: 0, last_nudge_topic: nil}

  @impl true
  def handle_event(%Event{topic: topic} = event, state) do
    %{
      state
      | events: [event | state.events],
        nudge_count: state.nudge_count + 1,
        last_nudge_topic: topic
    }
  end

  @impl true
  def ready?(state, :event), do: state.nudge_count >= @nudge_threshold
  def ready?(_state, _trigger), do: false

  @impl true
  def build_signal(state) do
    Signal.new("agent.unresponsive", state.key, Enum.reverse(state.events), %{
      nudge_count: state.nudge_count,
      last_nudge: state.last_nudge_topic
    })
  end

  @impl true
  def reset(state), do: %{state | events: [], nudge_count: 0, last_nudge_topic: nil}
end
