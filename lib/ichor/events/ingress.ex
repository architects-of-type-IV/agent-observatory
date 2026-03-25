defmodule Ichor.Events.Ingress do
  @moduledoc """
  GenStage producer that bridges domain events into the demand-driven signal pipeline.
  Events are pushed via `push/1` and buffered until downstream consumers demand them.
  """

  use GenStage

  alias Ichor.Events.Event

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec push(Event.t()) :: :ok
  def push(%Event{} = event) do
    GenStage.cast(__MODULE__, {:push, event})
  end

  @impl true
  def init(_opts) do
    {:producer, %{queue: :queue.new()}, dispatcher: GenStage.BroadcastDispatcher}
  end

  @impl true
  def handle_cast({:push, event}, %{queue: queue} = state) do
    {:noreply, [], %{state | queue: :queue.in(event, queue)}}
  end

  @impl true
  def handle_demand(demand, %{queue: queue} = state) when demand > 0 do
    {events, remaining} = take_from_queue(queue, demand, [])
    {:noreply, events, %{state | queue: remaining}}
  end

  defp take_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}

  defp take_from_queue(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, event}, rest} -> take_from_queue(rest, n - 1, [event | acc])
      {:empty, _} -> {Enum.reverse(acc), queue}
    end
  end
end
