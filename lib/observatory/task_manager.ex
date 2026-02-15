defmodule Observatory.TaskManager do
  @moduledoc """
  Task CRUD operations for file-based task storage.
  Tasks are stored as JSON files in ~/.claude/tasks/{team_name}/{id}.json
  """
  require Logger

  @tasks_base_dir Path.expand("~/.claude/tasks")

  # ═══════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════

  @doc """
  Create a new task for a team.
  Writes to ~/.claude/tasks/{team_name}/{id}.json
  """
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

  @doc """
  Update an existing task by merging changes.
  Reads, merges changes, and writes back to disk.
  """
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

  @doc """
  Get a task by ID.
  """
  def get_task(team_name, task_id) do
    file_path = task_file_path(team_name, task_id)

    case read_task_file(file_path) do
      {:ok, task} -> {:ok, task}
      {:error, :enoent} -> {:error, :task_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all tasks for a team.
  """
  def list_tasks(team_name) do
    team_dir = team_directory(team_name)

    if File.dir?(team_dir) do
      team_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn file ->
        file_path = Path.join(team_dir, file)

        case read_task_file(file_path) do
          {:ok, task} -> task
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn task -> String.to_integer(task["id"]) end)
    else
      []
    end
  end

  @doc """
  Delete a task.
  """
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

  @doc """
  Get the next available task ID for a team.
  Scans existing tasks and returns max ID + 1.
  """
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

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp team_directory(team_name) do
    Path.join(@tasks_base_dir, team_name)
  end

  defp task_file_path(team_name, task_id) do
    Path.join(team_directory(team_name), "#{task_id}.json")
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
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
end
