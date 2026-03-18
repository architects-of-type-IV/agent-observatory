defmodule Ichor.Dag.Validator do
  @moduledoc """
  Pure preflight validation functions for DAG items.

  All functions take lists of normalized maps with at minimum
  :id and :blocked_by keys. No DB calls, no side effects.

  Used by Ichor.Dag.validate_run/1 (domain entry point) and
  Dag.Spawner before launching a run.
  """

  @type item :: %{
          required(:id) => String.t(),
          required(:blocked_by) => [String.t()],
          optional(:allowed_files) => [String.t()],
          optional(:done_when) => String.t() | nil
        }

  @type issue :: %{
          type: atom(),
          severity: :error | :warning,
          external_id: String.t(),
          description: String.t()
        }

  @doc """
  Detects circular dependencies in the blocked_by graph.

  Returns a list of `{id_a, id_b}` pairs where both A->B and B->A exist,
  representing minimal bidirectional cycles. Does not enumerate all paths.
  """
  @spec detect_cycles([item()]) :: [{String.t(), String.t()}]
  def detect_cycles(items) do
    edges = build_edges(items)

    for {a, b} <- edges,
        {^b, ^a} <- edges,
        a < b,
        do: {a, b}
  end

  @doc """
  Finds items that share allowed_files but have no blocking relationship between them.

  Overlapping file scopes without explicit ordering can cause write conflicts.
  Returns `[{id_a, id_b, [shared_files]}]` for each unordered conflicting pair.
  """
  @spec file_overlap_deps([item()]) :: [{String.t(), String.t(), [String.t()]}]
  def file_overlap_deps(items) do
    items_with_files = Enum.filter(items, &has_files?/1)
    edge_set = build_edge_set(items)

    for {a, b} <- pairs(items_with_files),
        shared = shared_files(a, b),
        shared != [],
        not ordered?(a.id, b.id, edge_set),
        do: {a.id, b.id, shared}
  end

  @doc """
  Verifies that every blocked_by reference resolves to an existing item ID.

  Returns `[{id, [missing_ref_ids]}]` for items that reference non-existent IDs.
  """
  @spec flat_dag_check([item()]) :: [{String.t(), [String.t()]}]
  def flat_dag_check(items) do
    known_ids = MapSet.new(items, & &1.id)

    items
    |> Enum.map(&check_refs(&1, known_ids))
    |> Enum.reject(fn {_id, missing} -> missing == [] end)
  end

  @doc """
  Basic preflight checks on item metadata.

  Checks:
  - Items with no done_when (warning: no verification command)
  - Items with allowed_files that don't exist on disk (warning: stale file scope)

  Returns a list of issue maps with :type, :severity, :external_id, :description.
  """
  @spec preflight([item()]) :: [issue()]
  def preflight(items) do
    Enum.flat_map(items, &check_item/1)
  end

  # --- private helpers ---

  defp build_edges(items) do
    for item <- items, dep <- item.blocked_by, do: {item.id, dep}
  end

  defp build_edge_set(items) do
    items
    |> build_edges()
    |> MapSet.new()
  end

  defp has_files?(%{allowed_files: [_ | _]}), do: true
  defp has_files?(_), do: false

  defp pairs([]), do: []
  defp pairs([_ | rest] = list), do: for(a <- list, b <- rest, a != b, a.id < b.id, do: {a, b})

  defp shared_files(a, b) do
    a_files = MapSet.new(Map.get(a, :allowed_files, []))
    b_files = MapSet.new(Map.get(b, :allowed_files, []))
    a_files |> MapSet.intersection(b_files) |> MapSet.to_list()
  end

  defp ordered?(id_a, id_b, edge_set) do
    MapSet.member?(edge_set, {id_a, id_b}) or MapSet.member?(edge_set, {id_b, id_a})
  end

  defp check_refs(%{id: id, blocked_by: deps}, known_ids) do
    missing = Enum.reject(deps, &MapSet.member?(known_ids, &1))
    {id, missing}
  end

  defp check_item(%{id: id} = item) do
    [check_done_when(id, item), check_files(id, item)]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp check_done_when(id, %{done_when: nil}) do
    %{
      type: :missing_done_when,
      severity: :warning,
      external_id: id,
      description: "No done_when verification command"
    }
  end

  defp check_done_when(id, item) when not is_map_key(item, :done_when) do
    %{
      type: :missing_done_when,
      severity: :warning,
      external_id: id,
      description: "No done_when verification command"
    }
  end

  defp check_done_when(_id, _item), do: nil

  defp check_files(id, item) do
    item
    |> Map.get(:allowed_files, [])
    |> Enum.reject(&File.exists?/1)
    |> Enum.map(fn path ->
      %{
        type: :missing_file,
        severity: :warning,
        external_id: id,
        description: "File does not exist on disk: #{path}"
      }
    end)
  end
end
