defmodule Ichor.Events.Ingress do
  @moduledoc """
  GenStage producer. Bridges the event bus into demand-driven flow.

  Events are pushed via `push/1` and dispatched to consumers (the Signal Router)
  based on demand. Uses an internal queue to buffer events when demand is zero.
  """

  use GenStage

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec push(Ichor.Events.Event.t()) :: :ok
  def push(event) do
    GenServer.cast(__MODULE__, {:push, event})
  end

  @impl true
  def init(:ok) do
    {:producer, {:queue.new(), 0}}
  end

  @impl true
  def handle_cast({:push, event}, {queue, demand}) do
    queue = :queue.in(event, queue)
    dispatch_events(queue, demand, [])
  end

  @impl true
  def handle_demand(incoming_demand, {queue, demand}) do
    dispatch_events(queue, demand + incoming_demand, [])
  end

  defp dispatch_events(queue, demand, events) when demand > 0 do
    case :queue.out(queue) do
      {{:value, event}, queue} ->
        dispatch_events(queue, demand - 1, [event | events])

      {:empty, queue} ->
        {:noreply, Enum.reverse(events), {queue, demand}}
    end
  end

  defp dispatch_events(queue, 0, events) do
    {:noreply, Enum.reverse(events), {queue, 0}}
  end
end
