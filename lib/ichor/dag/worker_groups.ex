defmodule Ichor.Dag.WorkerGroups do
  @moduledoc """
  Pure grouping: jobs sharing any allowed_file must share a worker.
  Produces named worker groups for upfront agent spawning.
  """

  @doc "Groups jobs by shared file ownership, assigning each group a worker name."
  @spec group([struct() | map()]) :: [map()]
  def group([]), do: []

  def group(jobs) do
    jobs
    |> Enum.reduce([], &merge_into_groups/2)
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {group, idx} ->
      %{
        name: "worker-#{idx}",
        files: group.files,
        jobs: Enum.sort_by(group.jobs, & &1.wave)
      }
    end)
  end

  defp merge_into_groups(%{allowed_files: []} = job, groups) do
    [%{files: [], jobs: [job]} | groups]
  end

  defp merge_into_groups(job, groups) do
    file_set = MapSet.new(job.allowed_files)

    case find_overlap(file_set, groups) do
      {idx, existing} ->
        merged = %{
          files: Enum.uniq(existing.files ++ job.allowed_files),
          jobs: [job | existing.jobs]
        }

        List.replace_at(groups, idx, merged)

      nil ->
        [%{files: job.allowed_files, jobs: [job]} | groups]
    end
  end

  defp find_overlap(file_set, groups) do
    groups
    |> Enum.with_index()
    |> Enum.find_value(fn {group, idx} ->
      case MapSet.disjoint?(file_set, MapSet.new(group.files)) do
        false -> {idx, group}
        true -> nil
      end
    end)
  end
end
