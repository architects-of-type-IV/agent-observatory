defmodule Ichor.Signals.Pipeline.Stalled do
  @moduledoc """
  Fires when a pipeline run has no task progress for a sustained period.

  Watches `pipeline.task.claimed` and `pipeline.task.completed` events keyed
  by run_id. Each task event resets the stall timer. If the timer fires
  without progress, the signal activates.

  Key: run_id
  Fires: "pipeline.stalled" with stalled_for_seconds in metadata
  """

  use Ichor.Signal

  @stall_threshold_seconds 300

  @impl true
  def topics, do: ["pipeline.task.claimed", "pipeline.task.completed"]

  @impl true
  def init_state(key) do
    %{key: key, events: [], last_progress_at: System.monotonic_time(:second), metadata: %{}}
  end

  @impl true
  def handle_event(state, _event) do
    %{state | last_progress_at: System.monotonic_time(:second)}
  end

  @impl true
  def ready?(_state, :event), do: false

  def ready?(state, :timer) do
    stalled_for = System.monotonic_time(:second) - state.last_progress_at
    stalled_for >= @stall_threshold_seconds
  end

  @impl true
  def build_signal(state) do
    stalled_for = System.monotonic_time(:second) - state.last_progress_at

    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      [],
      %{stalled_for_seconds: stalled_for, threshold: @stall_threshold_seconds}
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    require Logger

    Logger.warning(
      "[Signal] #{signal.name} run=#{signal.key} stalled_for=#{signal.metadata[:stalled_for_seconds]}s"
    )

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Pipeline #{signal.key} stalled: no task progress for #{signal.metadata[:stalled_for_seconds]}s",
      type: :alert
    })

    :ok
  end

  @impl true
  def reset(state),
    do: %{state | events: [], last_progress_at: System.monotonic_time(:second), metadata: %{}}
end
