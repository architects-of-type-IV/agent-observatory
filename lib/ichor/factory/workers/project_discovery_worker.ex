defmodule Ichor.Factory.Workers.ProjectDiscoveryWorker do
  @moduledoc """
  Oban cron worker that scans discovery directories for tasks.jsonl projects,
  computes the full board state (tasks, dependency graph, pipeline stats),
  and emits a `:pipeline_status` signal.

  Runs on the `:maintenance` queue every minute via Oban cron.
  LiveView subscribers receive the updated board state via the signal.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 1, unique: [period: 55]

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.PipelineQuery

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    projects = PipelineQuery.projects()
    ensure_settings_projects(PipelineQuery.discover_from_events())

    active_project = first_project_key(projects)
    board = PipelineQuery.board_state(projects, active_project)

    state_map = Map.put(board, :health, %{})

    Events.emit(Event.new("pipeline.status", nil, %{state_map: state_map}))

    :ok
  end

  defp ensure_settings_projects(event_projects) do
    case Ichor.Settings.list_settings_projects() do
      {:ok, existing} ->
        known_paths = MapSet.new(existing, fn p -> p.location.path end)
        Enum.each(event_projects, &maybe_register_project(&1, known_paths))

      {:error, reason} ->
        Logger.warning("ensure_settings_projects: #{inspect(reason)}")
    end
  end

  defp maybe_register_project({name, path}, known_paths) do
    unless MapSet.member?(known_paths, path) do
      case Ichor.Settings.create_settings_project(%{
             name: name,
             location: %{type: :local, path: path}
           }) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("Auto-register project #{name}: #{inspect(reason)}")
      end
    end
  end

  defp first_project_key(projects) when map_size(projects) == 0, do: nil
  defp first_project_key(projects), do: projects |> Map.keys() |> hd()
end
