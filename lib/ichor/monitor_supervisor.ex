defmodule Ichor.MonitorSupervisor do
  @moduledoc """
  Supervises monitoring and observability services: DAG runtime, protocol tracker,
  agent monitor, nudge escalator, and quality gate. Independent observers, one_for_one.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
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
