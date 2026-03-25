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
      {Ichor.Projector.EntropyTracker, []},
      {Ichor.Infrastructure.HITLRelay, []},
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
