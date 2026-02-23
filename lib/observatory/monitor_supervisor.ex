defmodule Observatory.MonitorSupervisor do
  @moduledoc """
  Supervises monitoring and observability services: swarm monitor, protocol tracker,
  and agent monitor. These are independent observers, so one_for_one is appropriate.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Observatory.SwarmMonitor, []},
      {Observatory.ProtocolTracker, []},
      {Observatory.AgentMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
