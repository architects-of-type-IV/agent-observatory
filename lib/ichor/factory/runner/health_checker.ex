defmodule Ichor.Factory.Runner.HealthChecker do
  @moduledoc """
  Pure health-checking algorithm for pipeline graph nodes.

  Takes a list of graph nodes and returns structured issue maps describing
  stale tasks, file conflicts, deadlocks, and orphaned tasks. No IO, no
  GenServer dependency.
  """

  alias Ichor.Factory.PipelineGraph

  @stale_threshold_min 10

  @doc """
  Returns all health issues for the given pipeline graph nodes at the given
  point in time.

  Issues are maps with keys: `:type`, `:severity`, `:external_id`,
  `:description`.
  """
  @spec health_issues([map()], DateTime.t()) :: [map()]
  def health_issues(nodes, now) do
    stale_health_issues(nodes, now) ++
      conflict_health_issues(nodes) ++
      deadlock_health_issues(nodes) ++
      orphan_health_issues(nodes)
  end

  defp stale_health_issues(nodes, now) do
    nodes
    |> PipelineGraph.stale_items(now, @stale_threshold_min)
    |> Enum.map(fn node ->
      %{
        type: :stale_in_progress,
        severity: :warning,
        external_id: node.id,
        description:
          "Task execution #{node.id} has been in_progress for over #{@stale_threshold_min} minutes"
      }
    end)
  end

  defp conflict_health_issues(nodes) do
    nodes
    |> PipelineGraph.file_conflicts()
    |> Enum.map(fn {a, b, files} ->
      %{
        type: :file_conflict,
        severity: :error,
        external_id: "#{a}+#{b}",
        description: "Tasks #{a} and #{b} share files: #{Enum.join(files, ", ")}"
      }
    end)
  end

  defp deadlock_health_issues(nodes) do
    failed = nodes |> Enum.filter(&(to_string(&1.status) == "failed")) |> MapSet.new(& &1.id)

    nodes
    |> Enum.filter(fn node ->
      to_string(node.status) == "pending" and
        Enum.any?(node.blocked_by, &MapSet.member?(failed, &1))
    end)
    |> Enum.map(fn node ->
      %{
        type: :deadlocked,
        severity: :error,
        external_id: node.id,
        description:
          "Pipeline task #{node.id} is blocked by failed dependency tasks: #{Enum.join(node.blocked_by, ", ")}"
      }
    end)
  end

  defp orphan_health_issues(nodes) do
    failed = nodes |> Enum.filter(&(to_string(&1.status) == "failed")) |> MapSet.new(& &1.id)

    nodes
    |> Enum.filter(fn node ->
      to_string(node.status) == "pending" and
        node.blocked_by != [] and
        Enum.all?(node.blocked_by, &MapSet.member?(failed, &1))
    end)
    |> Enum.map(fn node ->
      %{
        type: :orphaned,
        severity: :warning,
        external_id: node.id,
        description: "Pipeline task #{node.id} is pending but all blockers have failed"
      }
    end)
  end
end
