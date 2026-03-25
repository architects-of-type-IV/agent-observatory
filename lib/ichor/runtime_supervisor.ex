defmodule Ichor.RuntimeSupervisor do
  @moduledoc """
  Supervises independent runtime services under a single one_for_one supervisor.

  The GenStage pipeline (Ingress + Router) is nested under
  `Ichor.Signals.PipelineSupervisor` with a `rest_for_one` strategy so that a
  Router restart always re-subscribes to a live Ingress. ProcessRegistry and
  ProcessSupervisor are siblings here (not inside PipelineSupervisor) so that
  SignalProcesses survive a pipeline restart.
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
      # Signal process bookkeeping -- must start before PipelineSupervisor
      {Registry, keys: :unique, name: Ichor.Signals.ProcessRegistry},
      {DynamicSupervisor, name: Ichor.Signals.ProcessSupervisor, strategy: :one_for_one},

      # GenStage pipeline: Ingress + Router under rest_for_one (see PipelineSupervisor)
      Ichor.Signals.PipelineSupervisor,

      # Core infrastructure services
      {Ichor.MemoryStore, []},
      {Ichor.Signals.EventStream, []},

      # Infrastructure and signal-adjacent services
      {Ichor.Infrastructure.TmuxDiscovery, []},
      {Ichor.Infrastructure.OutputCapture, []},

      # Monitoring and observability services
      {Ichor.Projector.AgentWatchdog, []},
      {Ichor.Projector.ProtocolTracker, []},
      {Ichor.Projector.SignalBuffer, []},
      {Ichor.Projector.SignalManager, []},
      {Ichor.Projector.TeamWatchdog, []}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
