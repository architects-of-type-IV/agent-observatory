defmodule Ichor.Heartbeat do
  @moduledoc """
  Publishes a periodic heartbeat via PubSub. Subscribers react to the beat
  to perform periodic work (tmux refresh, stats recompute, registry sync,
  etc.) without each owning their own timer.

  Subscribe to the "heartbeat" PubSub topic to receive `{:heartbeat, count}`.
  """
  use GenServer

  @interval 5_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{count: 0}}
  end

  @impl true
  def handle_info(:beat, %{count: count} = state) do
    next = count + 1

    Ichor.Signal.emit(:heartbeat, %{count: next})

    # Maintenance jobs on heartbeat intervals
    run_maintenance(next)

    schedule()
    {:noreply, %{state | count: next}}
  end

  # Run maintenance at different cadences based on heartbeat count
  defp run_maintenance(count) do
    # Every 12 beats (1min): sweep stale agents from registry
    if rem(count, 12) == 0 do
      spawn(fn -> Ichor.Gateway.AgentRegistry.purge_stale() end)
    end
  end

  defp schedule, do: Process.send_after(self(), :beat, @interval)
end
