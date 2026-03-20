defmodule Ichor.SystemSupervisor do
  @moduledoc """
  Supervises all independent system services under a single one_for_one supervisor.

  All services here are independent -- no ordering dependency exists between
  them, so one_for_one is appropriate.

  Children (in start order):
    Core:    Observability.Janitor, MemoryStore, EventBuffer
    Gateway: TmuxDiscovery, EntropyTracker, HeartbeatManager, CronScheduler,
             WebhookRouter, HITLRelay, OutputCapture
    Monitor: AgentWatchdog, Projects.Runtime, ProtocolTracker, QualityGate,
             Signals.Buffer, Archon.SignalManager, Archon.TeamWatchdog
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
      # Core infrastructure services
      {Ichor.Observability.Janitor, []},
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
      {Ichor.AgentWatchdog, []},
      {Ichor.Projects.Runtime, []},
      {Ichor.ProtocolTracker, []},
      {Ichor.QualityGate, []},
      {Ichor.Signals.Buffer, []},
      {Ichor.Archon.SignalManager, []},
      {Ichor.Archon.TeamWatchdog, []}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
