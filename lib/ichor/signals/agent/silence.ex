defmodule Ichor.Signals.Agent.Silence do
  @moduledoc """
  Fires when an agent has produced no events for a sustained period.

  Watches `agent.event` (hook activity) keyed by session_id. Each event
  resets the silence timer. If the timer fires without an intervening event,
  the signal activates.

  Key: session_id
  Fires: "agent.silence" with silent_for_seconds in metadata
  """

  use Ichor.Signal

  @silence_threshold_seconds 60

  @impl true
  def topics, do: ["agent.event"]

  @impl true
  def init_state(key) do
    %{key: key, events: [], last_event_at: System.monotonic_time(:second), metadata: %{}}
  end

  @impl true
  def handle_event(state, _event) do
    %{state | last_event_at: System.monotonic_time(:second)}
  end

  @impl true
  def ready?(_state, :event), do: false

  def ready?(state, :timer) do
    silent_for = System.monotonic_time(:second) - state.last_event_at
    silent_for >= @silence_threshold_seconds
  end

  @impl true
  def build_signal(state) do
    silent_for = System.monotonic_time(:second) - state.last_event_at

    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      [],
      %{silent_for_seconds: silent_for, threshold: @silence_threshold_seconds}
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    require Logger

    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} silent_for=#{signal.metadata[:silent_for_seconds]}s"
    )

    :ok
  end

  @impl true
  def reset(state),
    do: %{state | events: [], last_event_at: System.monotonic_time(:second), metadata: %{}}
end
