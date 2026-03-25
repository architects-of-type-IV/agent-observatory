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
    {:producer, %{queue: :queue.new(), demand: 0}}
  end

  @impl true
  def handle_cast({:push, event}, %{demand: demand} = state) when demand > 0 do
    {:noreply, [event], %{state | demand: demand - 1}}
  end

  def handle_cast({:push, event}, %{queue: queue} = state) do
    {:noreply, [], %{state | queue: :queue.in(event, queue)}}
  end

  @impl true
  def handle_demand(incoming, %{queue: queue, demand: demand} = state) do
    total = demand + incoming
    {to_dispatch, remaining, taken} = take_from_queue(queue, total)
    {:noreply, to_dispatch, %{state | queue: remaining, demand: total - taken}}
  end

  defp take_from_queue(queue, max), do: take_from_queue(queue, max, [], 0)

  defp take_from_queue(queue, 0, acc, taken), do: {Enum.reverse(acc), queue, taken}

  defp take_from_queue(queue, n, acc, taken) do
    case :queue.out(queue) do
      {{:value, event}, rest} -> take_from_queue(rest, n - 1, [event | acc], taken + 1)
      {:empty, _} -> {Enum.reverse(acc), queue, taken}
    end
  end
end
