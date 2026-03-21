defmodule Ichor.Factory.WorkerGroups do
  @moduledoc "Groups pipeline tasks into worker assignments based on file ownership overlap."

  @type worker_group :: %{
          name: String.t(),
          capability: String.t(),
          jobs: [map()],
          allowed_files: [String.t()],
          waves: [non_neg_integer()]
        }

  @doc "Builds worker groups from a list of pipeline task records."
  @spec build(list()) :: [worker_group()]
  def build(jobs) do
    jobs
    |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
    |> group_by_files()
    |> Enum.map(&enrich_group/1)
  end

  @doc "Finds the file overlap between a file set and a list of groups."
  @spec find_overlap(MapSet.t(), [map()]) :: {non_neg_integer(), map()} | nil
  def find_overlap(file_set, groups) do
    groups
    |> Enum.with_index()
    |> Enum.find_value(fn {group, idx} ->
      case MapSet.disjoint?(file_set, MapSet.new(group.files)) do
        false -> {idx, group}
        true -> nil
      end
    end)
  end

  defp enrich_group(group) do
    %{
      name: group.name,
      capability: "builder",
      jobs: group.jobs,
      allowed_files: Enum.sort(group.files),
      waves: group.jobs |> Enum.map(&(&1.wave || 0)) |> Enum.uniq()
    }
  end

  defp group_by_files([]), do: []

  defp group_by_files(jobs) do
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
end
