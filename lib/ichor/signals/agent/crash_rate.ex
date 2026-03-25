defmodule Ichor.Signals.Agent.CrashRate do
  @moduledoc """
  Fires when agent crashes exceed a threshold within a sliding time window.

  Watches `agent.crashed` events keyed by team_name. Accumulates crash
  timestamps and fires when the count in the window exceeds the limit.

  Key: team_name (crashes are correlated per team, not per agent)
  Fires: "agent.crash.rate" with crash_count and window_seconds in metadata
  """

  use Ichor.Signal

  @window_seconds 300
  @crash_threshold 3

  @impl true
  def topics, do: ["agent.crashed"]

  @impl true
  def init_state(key) do
    %{key: key, events: [], crashes: [], metadata: %{}}
  end

  @impl true
  def handle_event(state, _event) do
    now = System.monotonic_time(:second)
    cutoff = now - @window_seconds
    crashes = [now | Enum.filter(state.crashes, &(&1 > cutoff))]

    %{state | crashes: crashes, metadata: %{crash_count: length(crashes)}}
  end

  @impl true
  def ready?(state, :event), do: length(state.crashes) >= @crash_threshold
  def ready?(_state, _trigger), do: false

  @impl true
  def build_signal(state) do
    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      [],
      %{crash_count: length(state.crashes), window_seconds: @window_seconds}
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    require Logger

    Logger.error(
      "[Signal] #{signal.name} team=#{signal.key} crashes=#{signal.metadata[:crash_count]} in #{signal.metadata[:window_seconds]}s"
    )

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Agent crash rate exceeded in team #{signal.key}: #{signal.metadata[:crash_count]} crashes",
      type: :alert
    })

    :ok
  end

  @impl true
  def reset(state), do: %{state | crashes: [], events: [], metadata: %{}}
end
