defmodule Ichor.Factory.Workers.ProjectDiscoveryWorker do
  @moduledoc """
  Oban cron worker that scans discovery directories for tasks.jsonl projects,
  computes the full board state (tasks, dependency graph, pipeline stats),
  and emits a `:pipeline_status` signal.

  Runs on the `:maintenance` queue every minute via Oban cron.
  LiveView subscribers receive the updated board state via the signal.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: 55]

  alias Ichor.Factory.PipelineQuery
  alias Ichor.Signals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    projects = PipelineQuery.projects()
    active_project = first_project_key(projects)
    board = PipelineQuery.board_state(projects, active_project)

    state_map = Map.put(board, :health, %{})

    Signals.emit(:pipeline_status, %{state_map: state_map})

    :ok
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()
end
