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

    schedule()
    {:noreply, %{state | count: next}}
  end

  defp schedule, do: Process.send_after(self(), :beat, @interval)
end
