defmodule Observatory.Heartbeat do
  @moduledoc """
  Publishes a periodic heartbeat through the Gateway. Subscribers react to
  the beat to perform periodic work (tmux refresh, stats recompute, registry
  sync, etc.) without each owning their own timer.

  The heartbeat broadcasts to "fleet:heartbeat" via the Gateway pipeline,
  which means it flows through validation, routing, and audit like any
  other message.

  Subscribe to "heartbeat" PubSub topic for the local notification.
  """
  use GenServer

  @interval 5_000
  @topic "heartbeat"

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

    # Broadcast through PubSub for local subscribers (LiveView, monitors)
    Phoenix.PubSub.broadcast(Observatory.PubSub, @topic, {:heartbeat, next})

    # Route through Gateway for protocol-level visibility (audit, tracing)
    Observatory.Gateway.Router.broadcast("fleet:heartbeat", %{
      content: "heartbeat",
      from: "system",
      type: :heartbeat,
      count: next
    })

    # Maintenance jobs on heartbeat intervals
    run_maintenance(next)

    schedule()
    {:noreply, %{state | count: next}}
  end

  # Run maintenance at different cadences based on heartbeat count
  defp run_maintenance(count) do
    # Every 60 beats (5min): sweep stale agents from registry
    if rem(count, 60) == 0 do
      spawn(fn -> Observatory.Gateway.AgentRegistry.purge_stale() end)
    end
  end

  defp schedule, do: Process.send_after(self(), :beat, @interval)
end
