defmodule Ichor.Signals.Router do
  @moduledoc """
  GenStage consumer that receives events from Ingress and routes them
  to matching Signal processes based on `accepts?/1`.

  Each signal module decides whether it accepts an event. One event
  can route to multiple signal modules.
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
    {:consumer, %{modules: signal_modules()},
     subscribe_to: [{Ichor.Events.Ingress, max_demand: 50}]}
  end

  @impl true
  def handle_events(events, _from, state) do
    Enum.each(events, &route(&1, state.modules))
    {:noreply, [], state}
  end

  @doc "Reload the signal module list from config."
  @spec refresh_modules() :: :ok
  def refresh_modules do
    GenStage.cast(__MODULE__, :refresh_modules)
  end

  @impl true
  def handle_cast(:refresh_modules, state) do
    {:noreply, [], %{state | modules: signal_modules()}}
  end

  defp route(%Event{} = event, modules) do
    modules
    |> Enum.filter(& &1.accepts?(event))
    |> Enum.each(fn module ->
      SignalProcess.push_event(module, event.key, event)
    end)
  end

  defp signal_modules do
    Application.get_env(:ichor, :signal_modules, [])
  end
end
