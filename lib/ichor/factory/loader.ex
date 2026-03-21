defmodule Ichor.Factory.Loader do
  @moduledoc "Loads pipeline task data from tasks.jsonl files or project roadmaps into Pipeline + PipelineTask Ash resources."

  alias Ichor.Factory.{
    Pipeline,
    PipelineCompiler,
    PipelineGraph,
    PipelineTask,
    Project
  }

  alias Ichor.Signals

  @doc "Creates a pipeline and pipeline tasks from a tasks.jsonl file path."
  @spec from_file(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  def from_file(tasks_jsonl_path, opts \\ []) do
    label = derive_label_from_path(tasks_jsonl_path, opts)
    tmux_session = Keyword.get(opts, :tmux_session)
    raw_items = parse_jsonl(tasks_jsonl_path)

    create_pipeline_with_tasks(raw_items, label, :imported, tmux_session, %{
      project_path: Path.dirname(tasks_jsonl_path)
    })
  end

  @doc "Creates a pipeline and pipeline tasks from a project roadmap hierarchy, archiving prior runs first."
  @spec from_project(String.t(), keyword()) :: {:ok, Pipeline.t()} | {:error, term()}
  def from_project(project_id, opts \\ []) do
    tmux_session = Keyword.get(opts, :tmux_session)
    archive_existing_runs_for_project(project_id)

    with {:ok, task_maps} <- PipelineCompiler.generate(project_id) do
      label = derive_label(project_id)
      raw_items = Enum.map(task_maps, &normalize_planning_map/1)

      create_pipeline_with_tasks(raw_items, label, :project, tmux_session, %{
        project_id: project_id
      })
    end
  end

  @spec create_pipeline_with_tasks([map()], String.t(), atom(), String.t() | nil, map()) ::
          {:ok, Pipeline.t()} | {:error, term()}
  def create_pipeline_with_tasks(raw_items, label, source, tmux_session, extra_attrs) do
    nodes = Enum.map(raw_items, &PipelineGraph.to_graph_node/1)
    waves = PipelineGraph.waves(nodes)
    wave_map = build_wave_map(waves)

    pipeline_attrs =
      Map.merge(extra_attrs, %{
        label: label,
        source: source,
        tmux_session: tmux_session
      })

    with {:ok, pipeline} <- Pipeline.create(pipeline_attrs),
         :ok <- create_pipeline_tasks(raw_items, pipeline.id, wave_map) do
      Signals.emit(:pipeline_created, %{
        run_id: pipeline.id,
        source: source,
        label: label,
        task_count: length(raw_items)
      })

      {:ok, pipeline}
    end
  end

  @spec parse_jsonl(String.t()) :: [map()]
  def parse_jsonl(path) do
    path
    |> File.stream!()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> map
        _ -> nil
      end
    end)
    |> Enum.reject(&(is_nil(&1) or &1["status"] == "deleted"))
  end

  @spec normalize_planning_map(map()) :: map()
  def normalize_planning_map(m), do: Map.put(m, "subtask_id", m["subtask_id"])

  @spec build_wave_map([[String.t()]]) :: %{String.t() => non_neg_integer()}
  def build_wave_map(waves) do
    waves
    |> Enum.with_index()
    |> Enum.flat_map(fn {ids, wave_num} ->
      Enum.map(ids, &{&1, wave_num})
    end)
    |> Map.new()
  end

  @spec parse_priority(String.t() | nil) :: :critical | :high | :medium | :low
  def parse_priority("critical"), do: :critical
  def parse_priority("high"), do: :high
  def parse_priority("medium"), do: :medium
  def parse_priority("low"), do: :low
  def parse_priority(_), do: :medium

  @spec archive_existing_runs_for_project(String.t()) :: :ok
  def archive_existing_runs_for_project(project_id) do
    case Pipeline.by_project(project_id) do
      {:ok, pipelines} -> Enum.each(pipelines, &Pipeline.archive/1)
      _ -> :ok
    end
  end

  @spec derive_label(String.t()) :: String.t()
  def derive_label(project_id) do
    case Project.get(project_id) do
      {:ok, project} -> project.title
      _ -> "Pipeline"
    end
  end

  defp create_pipeline_tasks(raw_items, run_id, wave_map) do
    results = Enum.map(raw_items, &PipelineTask.create(to_task_attrs(&1, run_id, wave_map)))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, {:pipeline_task_create_failed, reason}}
    end
  end

  defp to_task_attrs(item, run_id, wave_map) do
    %{
      run_id: run_id,
      external_id: item["id"],
      subtask_id: item["subtask_id"],
      subject: item["subject"],
      description: item["description"],
      goal: item["goal"],
      allowed_files: item["files"] || item["allowed_files"] || [],
      steps: item["steps"] || [],
      done_when: item["done_when"],
      blocked_by: item["blocked_by"] || [],
      priority: parse_priority(item["priority"]),
      wave: Map.get(wave_map, item["id"]),
      acceptance_criteria: item["acceptance_criteria"] || [],
      phase_label: item["feature"] || item["phase_label"],
      tags: item["tags"] || [],
      notes: item["notes"]
    }
  end

  defp derive_label_from_path(path, opts) do
    Keyword.get(opts, :label, Path.basename(Path.dirname(path)))
  end
end
