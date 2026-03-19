defmodule Ichor.Projects.Discovery do
  @moduledoc """
  Project discovery for the DAG runtime.

  Three sources, merged in ascending priority order:
  - Event-discovered: cwds from EventBuffer ETS (opportunistic)
  - Archives: ~/.claude/teams/.archive/ (historical)
  - Teams: ~/.claude/teams/ (authoritative)
  """

  alias Ichor.EventBuffer

  @teams_dir Path.expand("~/.claude/teams")
  @archive_dir Path.expand("~/.claude/teams/.archive")

  @spec discover_projects() :: %{String.t() => String.t()}
  def discover_projects do
    event_projects = discover_from_events()
    archive_projects = discover_from_archives()
    team_projects = discover_from_teams()

    event_projects
    |> Map.merge(archive_projects)
    |> Map.merge(team_projects)
  end

  @doc "Returns archive entry maps from ~/.claude/teams/.archive/."
  @spec scan_archives() :: [map()]
  def scan_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} -> Enum.map(entries, &parse_archive_entry/1)
      _ -> []
    end
  end

  defp discover_from_events do
    EventBuffer.unique_project_cwds()
    |> Enum.filter(fn cwd -> File.exists?(Path.join(cwd, "tasks.jsonl")) end)
    |> Map.new(fn cwd -> {Path.basename(cwd), cwd} end)
  end

  defp discover_from_teams do
    case File.ls(@teams_dir) do
      {:ok, entries} ->
        entries
        |> Enum.reject(&(&1 == ".archive"))
        |> Enum.reduce(%{}, &collect_project_from_config(&1, @teams_dir, &2))

      _ ->
        %{}
    end
  end

  defp discover_from_archives do
    case File.ls(@archive_dir) do
      {:ok, entries} ->
        Enum.reduce(entries, %{}, &collect_project_from_config(&1, @archive_dir, &2))

      _ ->
        %{}
    end
  end

  defp collect_project_from_config(name, dir, acc) do
    config_path = Path.join([dir, name, "config.json"])

    case read_team_project(config_path) do
      nil -> acc
      project_path -> Map.put(acc, Path.basename(project_path), project_path)
    end
  end

  defp read_team_project(config_path) do
    with {:ok, json} <- File.read(config_path),
         {:ok, config} <- Jason.decode(json) do
      members = config["members"] || []

      Enum.find_value(members, fn m -> m["cwd"] end)
    else
      _ -> nil
    end
  end

  defp parse_archive_entry(name) do
    archive_path = Path.join(@archive_dir, name)
    summary_path = Path.join(archive_path, "gc-summary.json")

    with {:ok, json} <- File.read(summary_path),
         {:ok, summary} <- Jason.decode(json) do
      %{
        team: summary["team"] || name,
        timestamp: summary["archived_at"],
        path: archive_path,
        task_count: get_in(summary, ["task_summary"]) |> total_from_summary()
      }
    else
      _ -> %{team: name, timestamp: nil, path: archive_path, task_count: 0}
    end
  end

  defp total_from_summary(nil), do: 0

  defp total_from_summary(summary) when is_list(summary) do
    Enum.reduce(summary, 0, fn item, acc -> acc + (item["count"] || 0) end)
  end

  defp total_from_summary(_), do: 0
end
