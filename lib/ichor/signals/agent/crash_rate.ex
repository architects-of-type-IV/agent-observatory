defmodule Ichor.Signals.Agent.CrashRate do
  @moduledoc """
  Fires when agent crashes exceed a threshold within a sliding time window.

  Key: team_name
  Fires: "agent.crash.rate"
  """

  use Ichor.Signal

  @accepted_topics ["agent.crashed"]
  @window_seconds 300
  @crash_threshold 3

  @impl true
  def name, do: :crash_rate

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key), do: %{key: key, events: [], crashes: []}

  @impl true
  def handle_event(_event, state) do
    now = System.monotonic_time(:second)
    cutoff = now - @window_seconds
    crashes = [now | Enum.filter(state.crashes, &(&1 > cutoff))]
    %{state | crashes: crashes}
  end

  @impl true
  def ready?(state, :event), do: length(state.crashes) >= @crash_threshold
  def ready?(_state, _trigger), do: false

  @impl true
  def build_signal(state) do
    Signal.new("agent.crash.rate", state.key, [], %{
      crash_count: length(state.crashes),
      window_seconds: @window_seconds
    })
  end

  @impl true
  def reset(state), do: %{state | crashes: [], events: []}
end
