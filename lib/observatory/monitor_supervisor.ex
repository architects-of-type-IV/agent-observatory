defmodule Observatory.MonitorSupervisor do
  @moduledoc """
  Supervises monitoring and observability services: swarm monitor, protocol tracker,
  agent monitor, nudge escalator, and quality gate. Independent observers, one_for_one.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Observatory.Heartbeat, []},
      {Observatory.SwarmMonitor, []},
      {Observatory.ProtocolTracker, []},
      {Observatory.AgentMonitor, []},
      {Observatory.NudgeEscalator, []},
      {Observatory.QualityGate, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
