defmodule Ichor.Signals.PipelineSupervisor do
  @moduledoc """
  Supervises the GenStage pipeline: Ingress (producer) and Router (consumer).

  Uses `rest_for_one` so that if Ingress crashes and restarts, Router is also
  restarted immediately. This is necessary because Router holds a GenStage
  subscription to Ingress by PID at init time -- a stale subscription after
  an Ingress restart would silently drop all events until Router also restarts.

  ProcessRegistry and ProcessSupervisor are intentionally NOT children here:
  they live in RuntimeSupervisor under `one_for_one` and must survive a
  pipeline restart so that in-flight SignalProcesses are not destroyed.
  """

  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Ichor.Events.Ingress,
      Ichor.Signals.Router
    ]

    # rest_for_one: if Ingress (index 0) restarts, Router (index 1) restarts too.
    # If Router crashes alone, only Router restarts (Ingress is unaffected).
    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end
end
