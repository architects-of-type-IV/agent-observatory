defmodule Ichor.Events.Ingress do
  @moduledoc """
  GenStage producer that bridges domain events into the demand-driven signal pipeline.
  Events are pushed via `push/1` and buffered until downstream consumers demand them.

  Domain events are also persisted asynchronously to StoredEvent for replay.
  Signal bridge events (metadata source: :signal_bridge) are excluded from persistence.
  """

  use GenStage

  alias Ichor.Events.Event
  alias Ichor.Events.StoredEvent

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
    maybe_persist(event)
    {:noreply, [event], %{state | demand: demand - 1}}
  end

  def handle_cast({:push, event}, %{queue: queue} = state) do
    maybe_persist(event)
    {:noreply, [], %{state | queue: :queue.in(event, queue)}}
  end

  @impl true
  def handle_demand(incoming, %{queue: queue, demand: demand} = state) do
    total = demand + incoming
    {to_dispatch, remaining, taken} = take_from_queue(queue, total)
    {:noreply, to_dispatch, %{state | queue: remaining, demand: total - taken}}
  end

  defp maybe_persist(%Event{metadata: %{source: :signal_bridge}}), do: :ok

  defp maybe_persist(%Event{} = event) do
    Task.Supervisor.start_child(Ichor.TaskSupervisor, fn ->
      StoredEvent.record(%{
        topic: event.topic,
        key: to_string(event.key || ""),
        occurred_at: event.occurred_at,
        causation_id: event.causation_id,
        correlation_id: event.correlation_id,
        data: event.data,
        metadata: event.metadata
      })
    end)
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
