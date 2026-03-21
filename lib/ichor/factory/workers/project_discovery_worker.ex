defmodule Ichor.Factory.Workers.ProjectDiscoveryWorker do
  @moduledoc """
  Oban cron worker that scans discovery directories for tasks.jsonl projects
  and emits a `:pipeline_status` signal with the discovered project map.

  Runs on the `:maintenance` queue every minute via Oban cron.
  LiveView subscribers receive the updated project list via the signal.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: 55]

  alias Ichor.Factory.PipelineQuery
  alias Ichor.Signals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    projects = PipelineQuery.projects()
    archives = PipelineQuery.archives()

    state_map = %{
      watched_projects: projects,
      active_project: first_project_key(projects),
      archives: archives,
      pipeline: %{pending: 0, in_progress: 0, completed: 0, failed: 0},
      health: %{}
    }

    Signals.emit(:pipeline_status, %{state_map: state_map})

    :ok
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()
end
