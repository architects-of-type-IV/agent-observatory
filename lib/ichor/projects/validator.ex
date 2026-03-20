defmodule Ichor.Projects.Validator do
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

  defp build_edges(items) do
    for item <- items, dep <- item.blocked_by, do: {item.id, dep}
  end

  defp check_refs(%{id: id, blocked_by: deps}, known_ids) do
    missing = Enum.reject(deps, &MapSet.member?(known_ids, &1))
    {id, missing}
  end
end
