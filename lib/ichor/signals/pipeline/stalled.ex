defmodule Ichor.Signals.Pipeline.Stalled do
  @moduledoc """
  Fires when a pipeline run has no task progress for a sustained period.

  Key: run_id
  Fires: "pipeline.stalled"
  """

  use Ichor.Signal

  @accepted_topics ["pipeline.task.claimed", "pipeline.task.completed"]
  @stall_threshold_seconds 300

  @impl true
  def name, do: :stalled

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key), do: %{key: key, events: [], last_progress_at: System.monotonic_time(:second)}

  @impl true
  def handle_event(_event, state) do
    %{state | last_progress_at: System.monotonic_time(:second)}
  end

  @impl true
  def ready?(_state, :event), do: false

  def ready?(state, :timer) do
    System.monotonic_time(:second) - state.last_progress_at >= @stall_threshold_seconds
  end

  @impl true
  def build_signal(state) do
    stalled_for = System.monotonic_time(:second) - state.last_progress_at

    Signal.new("pipeline.stalled", state.key, [], %{
      stalled_for_seconds: stalled_for,
      threshold: @stall_threshold_seconds
    })
  end

  @impl true
  def reset(state), do: %{state | events: [], last_progress_at: System.monotonic_time(:second)}
end
