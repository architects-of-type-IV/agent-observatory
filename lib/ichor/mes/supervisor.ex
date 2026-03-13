defmodule Ichor.Mes.Supervisor do
  @moduledoc """
  Top-level supervisor for the MES subsystem.

  Supervision tree (rest_for_one -- Registry must start before RunSupervisor):

      Mes.Supervisor
        +-- Registry (Ichor.Mes.Registry)          # names MES processes
        +-- DynamicSupervisor (Ichor.Mes.RunSupervisor)  # one child per run
        +-- Mes.Janitor                             # monitors RunProcesses, cleans orphans
        +-- Mes.ProjectIngestor                     # ingests project briefs
        +-- Mes.Scheduler                           # ticks every 60s, spawns teams

  Janitor uses Process.monitor on each RunProcess to guarantee cleanup
  even when terminate/2 does not fire (brutal kills, supervisor restarts).

  On start, ensures an "operator" AgentProcess exists in the fleet so that
  coordinator agents can send_message to "operator" and have it land in
  a real BEAM mailbox (triggering :message_delivered for ProjectIngestor).
  """

  use Supervisor

  alias Ichor.Fleet.{AgentProcess, FleetSupervisor}

  def start_link(opts) do
    result = Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    ensure_operator_process()
    result
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Ichor.Mes.Registry},
      {DynamicSupervisor, name: Ichor.Mes.RunSupervisor, strategy: :one_for_one},
      {Ichor.Mes.Janitor, []},
      {Ichor.Mes.ProjectIngestor, []},
      {Ichor.Mes.Scheduler, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 10, max_seconds: 60)
  end

  defp ensure_operator_process do
    if AgentProcess.alive?("operator") do
      Ichor.Signals.emit(:mes_operator_ensured, %{status: "already_alive"})
    else
      case FleetSupervisor.spawn_agent(
             id: "operator",
             role: :operator,
             capabilities: [:read, :write],
             metadata: %{source: :mes, cwd: File.cwd!()}
           ) do
        {:ok, _pid} ->
          Ichor.Signals.emit(:mes_operator_ensured, %{status: "created"})

        {:error, {:already_started, _pid}} ->
          Ichor.Signals.emit(:mes_operator_ensured, %{status: "already_alive"})

        {:error, _reason} ->
          :ok
      end
    end
  end
end
