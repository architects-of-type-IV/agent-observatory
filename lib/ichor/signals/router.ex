defmodule Ichor.Signals.Router do
  @moduledoc """
  GenStage consumer that receives events from Ingress and routes them
  to the appropriate Signal processes based on topic matching.

  Signal modules register their topics via `topics/0` callback.
  One event can route to multiple signal modules.
  """

  use GenStage

  require Logger

  alias Ichor.Events.Event
  alias Ichor.Signals.SignalProcess

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:consumer, %{routing_table: build_routing_table()},
     subscribe_to: [{Ichor.Events.Ingress, max_demand: 50}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    Enum.each(events, fn %Event{} = event ->
      modules = Map.get(state.routing_table, event.topic, [])

      Enum.each(modules, fn module ->
        SignalProcess.push_event(module, event.key, event)
      end)
    end)

    {:noreply, [], state}
  end

  @doc "Rebuild the routing table. Call after adding new signal modules."
  @spec refresh_routes() :: :ok
  def refresh_routes do
    GenStage.cast(__MODULE__, :refresh_routes)
  end

  @impl true
  def handle_cast(:refresh_routes, state) do
    {:noreply, [], %{state | routing_table: build_routing_table()}}
  end

  defp build_routing_table do
    signal_modules()
    |> Enum.flat_map(fn module ->
      Enum.map(module.topics(), fn topic -> {topic, module} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp signal_modules do
    Application.get_env(:ichor, :signal_modules, [])
  end
end
