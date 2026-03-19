defmodule Ichor.SystemSupervisor do
  @moduledoc """
  Supervises all independent system services under a single one_for_one supervisor.

  Combines the children previously spread across CoreSupervisor, GatewaySupervisor,
  and MonitorSupervisor. All services here are independent -- no ordering dependency
  exists between them, so one_for_one is appropriate.

  Children (in start order):
    Core:    EventJanitor, MemoryStore, EventBuffer
    Gateway: TmuxDiscovery, EntropyTracker, HeartbeatManager, CronScheduler,
             WebhookRouter, HITLRelay, OutputCapture
    Monitor: Heartbeat, Dag.Runtime, ProtocolTracker, AgentMonitor,
             NudgeEscalator, QualityGate, PaneMonitor, Signals.Buffer,
             Archon.SignalManager, Archon.TeamWatchdog
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Core infrastructure services
      {Ichor.EventJanitor, []},
      {Ichor.MemoryStore, []},
      {Ichor.EventBuffer, []},

      # Gateway services
      {Ichor.Gateway.TmuxDiscovery, []},
      {Ichor.Gateway.EntropyTracker, []},
      {Ichor.Gateway.HeartbeatManager, []},
      {Ichor.Gateway.CronScheduler, []},
      {Ichor.Gateway.WebhookRouter, []},
      {Ichor.Gateway.HITLRelay, []},
      {Ichor.Gateway.OutputCapture, []},

      # Monitoring and observability services
      {Ichor.Heartbeat, []},
      {Ichor.Dag.Runtime, []},
      {Ichor.ProtocolTracker, []},
      {Ichor.AgentMonitor, []},
      {Ichor.NudgeEscalator, []},
      {Ichor.QualityGate, []},
      {Ichor.PaneMonitor, []},
      {Ichor.Signals.Buffer, []},
      {Ichor.Archon.SignalManager, []},
      {Ichor.Archon.TeamWatchdog, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
