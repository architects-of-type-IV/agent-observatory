defmodule Ichor.Factory.LifecycleSupervisor do
  @moduledoc """
  Top-level supervisor for Factory planning and pipeline execution.

  It owns:
  - run supervisors for planning and build runs
  - project ingestion and research ingestion
  - completion handling

  The MES tick is now driven by Oban cron (`Workers.MesTick`).

  Operator delivery depends on an `operator` AgentProcess existing in the
  unified fleet runtime, so this supervisor ensures that process on startup.
  """
  use Supervisor

  alias Ichor.Infrastructure.{AgentProcess, FleetSupervisor}

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    case Supervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      {:ok, _pid} = result ->
        ensure_operator_process()
        result

      error ->
        error
    end
  end

  @impl true
  def init(_opts) do
    children = [
      {DynamicSupervisor, name: Ichor.Factory.BuildRunSupervisor, strategy: :one_for_one},
      {Ichor.Projector.MesProjectIngestor, []},
      {Ichor.Projector.MesResearchIngestor, []},
      {Ichor.Factory.CompletionHandler, []}
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
