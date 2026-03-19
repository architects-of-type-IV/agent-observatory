defmodule Ichor.Tasks.TeamStore do
  @moduledoc """
  File-backed team task storage under `~/.claude/tasks`.
  """

  require Logger

  @tasks_base_dir Path.expand("~/.claude/tasks")

  @doc "Create a new task file for the team and return the task map."
  @spec create_task(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_task(team_name, attrs) when is_map(attrs) do
    task_id = next_task_id(team_name)
    team_dir = team_directory(team_name)
    File.mkdir_p!(team_dir)

    task =
      Map.merge(attrs, %{
        "id" => to_string(task_id),
        "status" => attrs["status"] || "pending",
        "blocks" => attrs["blocks"] || [],
        "blockedBy" => attrs["blockedBy"] || [],
        "metadata" => attrs["metadata"] || %{}
      })

    file_path = task_file_path(team_name, task_id)

    case write_task_file(file_path, task) do
      :ok ->
        Logger.info("TaskManager: Created task #{task_id} for team #{team_name}")
        {:ok, task}

      {:error, reason} ->
        Logger.error("TaskManager: Failed to create task: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc "Deep-merge changes into an existing task file and return the updated task."
  @spec update_task(String.t(), String.t() | pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def update_task(team_name, task_id, changes) when is_map(changes) do
    file_path = task_file_path(team_name, task_id)

    case read_task_file(file_path) do
      {:ok, existing_task} ->
        updated_task = deep_merge(existing_task, changes)

        case write_task_file(file_path, updated_task) do
          :ok ->
            Logger.debug("TaskManager: Updated task #{task_id} in team #{team_name}")
            {:ok, updated_task}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :enoent} ->
        {:error, :task_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Read a single task file by id."
  @spec get_task(String.t(), String.t() | pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_task(team_name, task_id) do
    file_path = task_file_path(team_name, task_id)

    case read_task_file(file_path) do
      {:ok, task} -> {:ok, task}
      {:error, :enoent} -> {:error, :task_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Return all tasks for a team, sorted by numeric id."
  @spec list_tasks(String.t()) :: [map()]
  def list_tasks(team_name) do
    team_dir = team_directory(team_name)

    if File.dir?(team_dir) do
      team_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(&read_task_or_nil(team_dir, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn task -> String.to_integer(task["id"]) end)
    else
      []
    end
  end

  @doc "Delete a task file by id."
  @spec delete_task(String.t(), String.t() | pos_integer()) :: :ok | {:error, term()}
  def delete_task(team_name, task_id) do
    file_path = task_file_path(team_name, task_id)

    case File.rm(file_path) do
      :ok ->
        Logger.info("TaskManager: Deleted task #{task_id} from team #{team_name}")
        :ok

      {:error, :enoent} ->
        {:error, :task_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Return the next available task id for a team."
  @spec next_task_id(String.t()) :: pos_integer()
  def next_task_id(team_name) do
    team_dir = team_directory(team_name)

    if File.dir?(team_dir) do
      max_id =
        team_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn file ->
          file
          |> String.replace_suffix(".json", "")
          |> String.to_integer()
        end)
        |> Enum.max(fn -> 0 end)

      max_id + 1
    else
      1
    end
  end

  defp team_directory(team_name), do: Path.join(@tasks_base_dir, team_name)

  defp task_file_path(team_name, task_id),
    do: Path.join(team_directory(team_name), "#{task_id}.json")

  defp read_task_or_nil(team_dir, file) do
    case read_task_file(Path.join(team_dir, file)) do
      {:ok, task} -> task
      {:error, _} -> nil
    end
  end

  defp read_task_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            {:ok, data}

          {:error, reason} ->
            Logger.error("TaskManager: Failed to decode #{file_path}: #{inspect(reason)}")
            {:error, :invalid_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_task_file(file_path, task) do
    case Jason.encode(task, pretty: true) do
      {:ok, json} ->
        File.write(file_path, json)

      {:error, reason} ->
        Logger.error("TaskManager: Failed to encode task: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2), do: deep_merge(v1, v2), else: v2
    end)
  end
end
