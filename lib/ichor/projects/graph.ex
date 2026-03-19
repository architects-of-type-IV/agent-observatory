defmodule Ichor.Projects.Graph do
  @moduledoc "Pure DAG computation on normalized graph node maps."

  @doc "Normalize to graph node map. Accepts Job structs or string-key maps."
  @spec to_graph_node(struct() | map()) :: map()
  def to_graph_node(%{external_id: _external_id} = job) do
    %{
      id: job.external_id,
      status: to_string(job.status),
      blocked_by: job.blocked_by || [],
      allowed_files: job.allowed_files || [],
      owner: job.owner || "",
      updated_at: job.updated_at
    }
  end

  def to_graph_node(%{"id" => _} = m) do
    %{
      id: Map.get(m, "id", ""),
      status: Map.get(m, "status", "pending"),
      blocked_by: Map.get(m, "blocked_by", []),
      allowed_files: first_present(m, ["files", "allowed_files"], []),
      owner: Map.get(m, "owner", ""),
      updated_at: first_present(m, ["updated", "updated_at", "created"], "")
    }
  end

  def to_graph_node(%{id: _} = task) do
    %{
      id: Map.get(task, :id, ""),
      status: Map.get(task, :status, "pending"),
      blocked_by: Map.get(task, :blocked_by, []),
      allowed_files: first_present(task, [:files, :allowed_files], []),
      owner: Map.get(task, :owner, ""),
      updated_at: first_present(task, [:updated, :updated_at, :created], "")
    }
  end

  defp first_present(map, keys, default), do: Enum.find_value(keys, default, &Map.get(map, &1))

  @doc "Topological sort into execution waves. Wave 0 has no dependencies."
  @spec waves([map()]) :: [[String.t()]]
  def waves(items) do
    all_ids = items |> Enum.map(& &1.id) |> MapSet.new()
    do_compute_waves(items, all_ids, MapSet.new(), [], 0)
  end

  defp do_compute_waves(items, all_ids, assigned, waves, wave_num) do
    if MapSet.size(assigned) == MapSet.size(all_ids) or wave_num > 50 do
      Enum.reverse(waves)
    else
      wave =
        items
        |> Enum.filter(&wave_ready?(&1, assigned, all_ids))
        |> Enum.map(& &1.id)

      case wave do
        [] ->
          remaining = collect_remaining_ids(items, assigned)
          Enum.reverse([remaining | waves])

        _ ->
          new_assigned = Enum.reduce(wave, assigned, &MapSet.put(&2, &1))
          do_compute_waves(items, all_ids, new_assigned, [wave | waves], wave_num + 1)
      end
    end
  end

  defp wave_ready?(item, assigned, all_ids) do
    not MapSet.member?(assigned, item.id) and
      Enum.all?(item.blocked_by, fn dep ->
        MapSet.member?(assigned, dep) or not MapSet.member?(all_ids, dep)
      end)
  end

  defp collect_remaining_ids(items, assigned) do
    items |> Enum.reject(&MapSet.member?(assigned, &1.id)) |> Enum.map(& &1.id)
  end

  @doc "Returns `{from_id, to_id}` edge pairs from blocked_by relationships."
  @spec edges([map()]) :: [{String.t(), String.t()}]
  def edges(items) do
    Enum.flat_map(items, fn t -> Enum.map(t.blocked_by, &{&1, t.id}) end)
  end

  @doc "Returns a map with waves, edges, and critical_path for a DAG."
  @spec dag([map()]) :: %{
          waves: [[String.t()]],
          edges: [{String.t(), String.t()}],
          critical_path: [String.t()]
        }
  def dag(items),
    do: %{waves: waves(items), edges: edges(items), critical_path: critical_path(items)}

  @doc "Returns the longest dependency chain as an ordered list of item IDs."
  @spec critical_path([map()]) :: [String.t()]
  def critical_path(items) do
    task_map = Map.new(items, &{&1.id, &1})

    {_memo, lengths} =
      Enum.reduce(items, {%{}, %{}}, fn t, {m, l} ->
        {depth, m} = longest_chain(t.id, task_map, m)
        {m, Map.put(l, t.id, depth)}
      end)

    case Enum.max_by(lengths, fn {_id, depth} -> depth end, fn -> {nil, 0} end) do
      {nil, _} -> []
      {start_id, _} -> trace_critical_path(start_id, task_map)
    end
  end

  defp longest_chain(id, task_map, memo) do
    case Map.get(memo, id) do
      nil -> compute_chain_depth(id, task_map, memo)
      depth -> {depth, memo}
    end
  end

  defp compute_chain_depth(id, task_map, memo) do
    case Map.get(task_map, id) do
      nil ->
        {0, Map.put(memo, id, 0)}

      task ->
        {max_dep, memo} =
          Enum.reduce(task.blocked_by, {0, memo}, fn dep_id, {max, m} ->
            {depth, m} = longest_chain(dep_id, task_map, m)
            {max(max, depth), m}
          end)

        depth = max_dep + 1
        {depth, Map.put(memo, id, depth)}
    end
  end

  defp trace_critical_path(id, task_map) do
    case Map.get(task_map, id) do
      nil -> []
      task -> trace_from_task(id, task, task_map)
    end
  end

  defp trace_from_task(id, %{blocked_by: []}, _task_map), do: [id]

  defp trace_from_task(id, %{blocked_by: deps}, task_map) do
    longest_dep =
      deps
      |> Enum.map(&dep_path_length(&1, task_map))
      |> Enum.max_by(fn {_id, len} -> len end)
      |> elem(0)

    trace_critical_path(longest_dep, task_map) ++ [id]
  end

  defp dep_path_length(dep_id, task_map) do
    case Map.get(task_map, dep_id) do
      nil -> {dep_id, 0}
      _ -> {dep_id, length(trace_critical_path(dep_id, task_map))}
    end
  end

  @doc "Counts by status."
  @spec pipeline_stats([map()]) :: %{
          total: non_neg_integer(),
          pending: non_neg_integer(),
          in_progress: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          blocked: non_neg_integer()
        }
  def pipeline_stats(items) do
    %{
      total: length(items),
      pending: Enum.count(items, &(to_string(&1.status) == "pending")),
      in_progress: Enum.count(items, &(to_string(&1.status) == "in_progress")),
      completed: Enum.count(items, &(to_string(&1.status) == "completed")),
      failed: Enum.count(items, &(to_string(&1.status) == "failed")),
      blocked: Enum.count(items, &(to_string(&1.status) == "blocked"))
    }
  end

  @doc "Pending, unowned items with all blocked_by completed."
  @spec available([map()]) :: [map()]
  def available(items) do
    completed =
      items |> Enum.filter(&(to_string(&1.status) == "completed")) |> MapSet.new(& &1.id)

    Enum.filter(items, fn t ->
      to_string(t.status) == "pending" and (t.owner == nil or t.owner == "") and
        Enum.all?(t.blocked_by, &MapSet.member?(completed, &1))
    end)
  end

  @doc "Items in_progress longer than threshold_min minutes."
  @spec stale_items([map()], DateTime.t(), non_neg_integer()) :: [map()]
  def stale_items(items, now, threshold_min \\ 10) do
    Enum.filter(items, fn t ->
      to_string(t.status) == "in_progress" and stale?(t, now, threshold_min)
    end)
  end

  defp stale?(item, now, threshold_min) do
    case parse_timestamp(item.updated_at) do
      nil -> true
      ts -> DateTime.diff(now, ts, :minute) > threshold_min
    end
  end

  defp parse_timestamp(""), do: nil

  defp parse_timestamp(str) when is_binary(str) do
    str = String.replace(str, "Z", "")

    case DateTime.from_iso8601(str <> "Z") do
      {:ok, dt, _} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp parse_timestamp(_), do: nil

  @doc "Returns `{id_a, id_b, shared_files}` triples for in_progress items sharing files."
  @spec file_conflicts([map()]) :: [{String.t(), String.t(), [String.t()]}]
  def file_conflicts(items) do
    in_progress = Enum.filter(items, &(to_string(&1.status) == "in_progress"))

    for a <- in_progress,
        b <- in_progress,
        a.id < b.id,
        shared = Enum.filter(a.allowed_files, &(&1 in b.allowed_files)),
        shared != [] do
      {a.id, b.id, shared}
    end
  end
end
