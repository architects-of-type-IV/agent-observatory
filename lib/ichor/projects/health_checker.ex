defmodule Ichor.Projects.HealthChecker do
  @moduledoc """
  Health check for a DAG run.

  Two entry points:
  - `analyze/2` -- pure: takes loaded Job structs + DateTime, returns health report
  - `check/1`   -- DB-aware: loads Jobs then delegates to analyze/2
  """

  alias Ichor.Projects.{Graph, Job}

  @stale_threshold_min 10

  @type issue :: %{
          type: atom(),
          severity: :warning | :error,
          external_id: String.t(),
          description: String.t()
        }

  @type report :: %{
          healthy: boolean(),
          issues: [issue()],
          stats: map()
        }

  @spec check(String.t()) :: {:ok, report()} | {:error, term()}
  def check(run_id) do
    with {:ok, jobs} <- Job.by_run(run_id) do
      {:ok, analyze(jobs, DateTime.utc_now())}
    end
  end

  @spec analyze([struct() | map()], DateTime.t()) :: report()
  def analyze(jobs, now) do
    nodes = Enum.map(jobs, &Graph.to_graph_node/1)
    stats = Graph.pipeline_stats(nodes)

    issues =
      stale_issues(nodes, now) ++
        conflict_issues(nodes) ++
        deadlock_issues(nodes) ++
        orphan_issues(nodes)

    %{
      healthy: issues == [],
      issues: issues,
      stats: stats
    }
  end

  defp stale_issues(nodes, now) do
    nodes
    |> Graph.stale_items(now, @stale_threshold_min)
    |> Enum.map(fn node ->
      %{
        type: :stale_in_progress,
        severity: :warning,
        external_id: node.id,
        description:
          "Job #{node.id} has been in_progress for over #{@stale_threshold_min} minutes"
      }
    end)
  end

  defp conflict_issues(nodes) do
    nodes
    |> Graph.file_conflicts()
    |> Enum.map(fn {a, b, files} ->
      %{
        type: :file_conflict,
        severity: :error,
        external_id: "#{a}+#{b}",
        description: "Jobs #{a} and #{b} share files: #{Enum.join(files, ", ")}"
      }
    end)
  end

  defp deadlock_issues(nodes) do
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
          "Job #{node.id} is blocked by failed job(s): #{Enum.join(node.blocked_by, ", ")}"
      }
    end)
  end

  defp orphan_issues(nodes) do
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
        description: "Job #{node.id} is pending but all blockers have failed"
      }
    end)
  end
end
