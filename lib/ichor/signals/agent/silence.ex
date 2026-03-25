defmodule Ichor.Signals.Agent.Silence do
  @moduledoc """
  Fires when an agent produces no events for a sustained period.

  Key: session_id
  Fires: "agent.silence"
  """

  use Ichor.Signal

  @accepted_topics ["agent.event"]
  @silence_threshold_seconds 60

  @impl true
  def name, do: :silence

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key), do: %{key: key, events: [], last_event_at: System.monotonic_time(:second)}

  @impl true
  def handle_event(_event, state) do
    %{state | last_event_at: System.monotonic_time(:second)}
  end

  @impl true
  def ready?(_state, :event), do: false

  def ready?(state, :timer) do
    System.monotonic_time(:second) - state.last_event_at >= @silence_threshold_seconds
  end

  @impl true
  def build_signal(state) do
    silent_for = System.monotonic_time(:second) - state.last_event_at

    Signal.new("agent.silence", state.key, [], %{
      silent_for_seconds: silent_for,
      threshold: @silence_threshold_seconds
    })
  end

  @impl true
  def reset(state), do: %{state | events: [], last_event_at: System.monotonic_time(:second)}
end
