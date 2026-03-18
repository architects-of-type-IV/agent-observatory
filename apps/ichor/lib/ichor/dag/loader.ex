defmodule Ichor.Dag.Loader do
  @moduledoc "Loads tasks into Dag.Run + Dag.Job records from tasks.jsonl or Genesis hierarchy."

  alias Ichor.Dag.{Graph, Job, Run, RuntimeSignals}
  alias Ichor.Genesis.DagGenerator
  alias Ichor.Genesis.Node, as: GenesisNode

  @spec from_file(String.t(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def from_file(tasks_jsonl_path, opts \\ []) do
    label = Keyword.get(opts, :label, Path.basename(Path.dirname(tasks_jsonl_path)))
    tmux_session = Keyword.get(opts, :tmux_session)
    raw_items = parse_jsonl(tasks_jsonl_path)

    create_run_with_jobs(raw_items, label, :imported, tmux_session, %{
      project_path: Path.dirname(tasks_jsonl_path)
    })
  end

  @spec from_genesis(String.t(), keyword()) :: {:ok, Run.t()} | {:error, term()}
  def from_genesis(node_id, opts \\ []) do
    tmux_session = Keyword.get(opts, :tmux_session)
    archive_existing_runs_for_node(node_id)

    with {:ok, task_maps} <- DagGenerator.generate(node_id) do
      label = derive_label(node_id)
      raw_items = Enum.map(task_maps, &normalize_genesis_map/1)
      create_run_with_jobs(raw_items, label, :genesis, tmux_session, %{node_id: node_id})
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp create_run_with_jobs(raw_items, label, source, tmux_session, extra_attrs) do
    nodes = Enum.map(raw_items, &Graph.to_graph_node/1)
    waves = Graph.waves(nodes)
    wave_map = build_wave_map(waves)

    run_attrs =
      Map.merge(extra_attrs, %{
        label: label,
        source: source,
        tmux_session: tmux_session,
        job_count: length(raw_items)
      })

    with {:ok, run} <- Run.create(run_attrs),
         :ok <- create_jobs(raw_items, run.id, wave_map) do
      RuntimeSignals.emit_run_created(run.id, source, label, length(raw_items))

      {:ok, run}
    end
  end

  defp create_jobs(raw_items, run_id, wave_map) do
    results = Enum.map(raw_items, &Job.create(to_job_attrs(&1, run_id, wave_map)))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> :ok
      {:error, reason} -> {:error, {:job_create_failed, reason}}
    end
  end

  defp to_job_attrs(item, run_id, wave_map) do
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

  defp normalize_genesis_map(m) do
    Map.put(m, "subtask_id", m["subtask_id"])
  end

  defp parse_jsonl(path) do
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

  defp build_wave_map(waves) do
    waves
    |> Enum.with_index()
    |> Enum.flat_map(fn {ids, wave_num} ->
      Enum.map(ids, &{&1, wave_num})
    end)
    |> Map.new()
  end

  defp parse_priority("critical"), do: :critical
  defp parse_priority("high"), do: :high
  defp parse_priority("medium"), do: :medium
  defp parse_priority("low"), do: :low
  defp parse_priority(_), do: :medium

  defp archive_existing_runs_for_node(node_id) do
    case Run.by_node(node_id) do
      {:ok, runs} -> Enum.each(runs, &Run.archive/1)
      _ -> :ok
    end
  end

  defp derive_label(node_id) do
    case GenesisNode.get(node_id) do
      {:ok, node} -> node.title
      _ -> "DAG Run"
    end
  end
end
