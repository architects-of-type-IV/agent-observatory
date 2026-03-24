defmodule Ichor.Projector.Router do
  @moduledoc """
  GenStage consumer that routes events to signal processes.

  Subscribes to the Ingress producer and checks each event against
  registered signal modules' `topics/0`. Routes matching events to
  the appropriate SignalProcess keyed by `{module, event.key}`.
  """

  use GenStage

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenStage.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Returns the list of registered signal modules."
  @spec signal_modules() :: [module()]
  def signal_modules do
    Application.get_env(:ichor, :signal_modules, [])
  end

  @impl true
  def init(:ok) do
    {:consumer, :ok, subscribe_to: [{Ichor.Events.Ingress, max_demand: 50}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    modules = signal_modules()

    Enum.each(events, fn event ->
      Enum.each(modules, fn mod ->
        if event.topic in mod.topics() do
          Ichor.Projector.SignalProcess.route(mod, event)
        end
      end)
    end)

    {:noreply, [], state}
  end
end
