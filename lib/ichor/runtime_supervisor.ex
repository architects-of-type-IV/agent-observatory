defmodule Ichor.RuntimeSupervisor do
  @moduledoc """
  Supervises independent runtime services under a single one_for_one supervisor.
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
      {Ichor.MemoryStore, []},
      {Ichor.Signals.EventStream, []},

      # Infrastructure and signal-adjacent services
      {Ichor.Infrastructure.TmuxDiscovery, []},
      {Ichor.Signals.EntropyTracker, []},
      {Ichor.Infrastructure.HITLRelay, []},
      {Ichor.Infrastructure.OutputCapture, []},

      # Monitoring and observability services
      {Ichor.Signals.AgentWatchdog, []},
      {Ichor.Factory.PipelineMonitor, []},
      {Ichor.Signals.ProtocolTracker, []},
      {Ichor.Signals.Buffer, []},
      {Ichor.Archon.SignalManager, []},
      {Ichor.Archon.TeamWatchdog, []}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
