defmodule Ichor.Projects.LifecycleSupervisor do
  @moduledoc """
  Top-level supervisor for the MES subsystem.

  Supervision tree:

      Mes.Supervisor
        +-- DynamicSupervisor (Ichor.Projects.BuildRunSupervisor)  # one child per run
        +-- Mes.Janitor                             # monitors RunProcesses, cleans orphans
        +-- Mes.ProjectIngestor                     # ingests project briefs
        +-- Mes.ResearchIngestor                    # ingests briefs into knowledge graph
      +-- Mes.Scheduler                           # ticks every 60s, spawns teams

  MES agents now live under Fleet.TeamSupervisor (via FleetSupervisor), sharing
  the unified supervision tree with all other agents.

  All processes register in the unified Ichor.Registry (started in Application).
  Janitor uses Process.monitor on each RunProcess to guarantee cleanup
  even when terminate/2 does not fire (brutal kills, supervisor restarts).

  On start, ensures an "operator" AgentProcess exists in the fleet so that
  coordinator agents can send_message to "operator" and have it land in
  a real BEAM mailbox (triggering :message_delivered for ProjectIngestor).
  """

  use Supervisor

  alias Ichor.Control.{AgentProcess, FleetSupervisor}

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    result = Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    ensure_operator_process()
    result
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Projects.BuildRunSupervisor, strategy: :one_for_one},
      {Ichor.Projects.Janitor, []},
      {Ichor.Projects.ProjectIngestor, []},
      {Ichor.Projects.ResearchIngestor, []},
      {Ichor.Projects.CompletionHandler, []},
      {Ichor.Projects.Scheduler, []}
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
