defmodule Ichor.Factory.LifecycleSupervisor do
  @moduledoc """
  Top-level supervisor for the MES pipeline.

  Supervision tree:

      Mes.Supervisor
        +-- DynamicSupervisor (Ichor.Factory.BuildRunSupervisor)  # one child per run
        +-- Mes.ProjectIngestor                                   # ingests project briefs
        +-- Mes.ResearchIngestor                                  # ingests briefs into knowledge graph
        +-- Mes.Scheduler                                         # ticks every 60s, spawns teams

  MES agents now live under Fleet.TeamSupervisor (via FleetSupervisor), sharing
  the unified supervision tree with all other agents.

  All processes register in the unified Ichor.Registry (started in Application).
  MES cleanup and orphan sweeping run through Oban maintenance workers.

  On start, ensures an "operator" AgentProcess exists in the fleet so that
  coordinator agents can send_message to "operator" and have it land in
  a real BEAM mailbox (triggering :message_delivered for ProjectIngestor).
  """
  # todo: moduledoc needs to be updated and understand it is not a diary/logbook
  use Supervisor

  alias Ichor.Factory.Runner
  alias Ichor.Factory.Workers.OrphanSweepWorker
  alias Ichor.Infrastructure.{AgentProcess, FleetSupervisor}
  alias Ichor.Signals

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    result = Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
    ensure_operator_process()
    ensure_orphan_sweep()
    result
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Factory.BuildRunSupervisor, strategy: :one_for_one},
      {Ichor.Factory.ProjectIngestor, []},
      {Ichor.Factory.ResearchIngestor, []},
      {Ichor.Factory.CompletionHandler, []},
      {Ichor.Factory.Scheduler, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 10, max_seconds: 60)
  end

  defp ensure_operator_process do
    if AgentProcess.alive?("operator") do
      # todo: mes_operator_ensured must be renamed, operator is more generic
      Ichor.Signals.emit(:mes_operator_ensured, %{status: "already_alive"})
    else
      # todo: tricky, FleetSupervisor must be started before this can succeed
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

  defp ensure_orphan_sweep do
    active_runs = length(Runner.list_all(:mes))
    # todo: janitor rename. This emit should trigger a oban job.
    Signals.emit(:mes_janitor_init, %{monitored: active_runs})
    # todo: oban needs to be configured else where
    unless oban_inline_testing?() do
      case OrphanSweepWorker.schedule(10) do
        {:ok, _job} -> :ok
        {:error, _reason} -> :ok
      end
    end
  end

  defp oban_inline_testing? do
    Application.get_env(:ichor, Oban, [])
    |> Keyword.get(:testing)
    |> Kernel.==(:inline)
  end
end
