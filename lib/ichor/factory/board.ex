defmodule Ichor.Factory.Board do
  @moduledoc """
  Unified action layer for team board tasks, including signal emission.

  Incorporates: TeamStore (file-backed per-team JSON task storage).
  """

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event

  @tasks_base_dir Path.expand("~/.claude/tasks")

  # ---------------------------------------------------------------------------
  # Signal-emitting public API (formerly Board)
  # ---------------------------------------------------------------------------

  @doc "Create a task and emit a task_created signal for the team."
  @spec create_task(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_task(team_name, attrs) do
    with {:ok, task} <- store_create_task(team_name, attrs) do
      emit(:task_created, team_name, %{task: task})
      {:ok, task}
    end
  end

  @doc "Update a task and emit a task_updated signal for the team."
  @spec update_task(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_task(team_name, task_id, changes) do
    with {:ok, task} <- store_update_task(team_name, task_id, changes) do
      emit(:task_updated, team_name, %{task: task})
      {:ok, task}
    end
  end

  @doc "Delete a task and emit a task_deleted signal for the team."
  @spec delete_task(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_task(team_name, task_id) do
    case store_delete_task(team_name, task_id) do
      :ok ->
        emit(:task_deleted, team_name, %{task_id: task_id})
        :ok

      error ->
        error
    end
  end

  @doc "Read a single task by id."
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
      |> read_json_tasks(team_dir)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(&task_sort_key/1)
    else
      []
    end
  end

  defp read_json_tasks(files, team_dir) do
    for f <- files, String.ends_with?(f, ".json"), do: read_task_or_nil(team_dir, f)
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
        |> Enum.flat_map(&parse_task_id_from_file/1)
        |> Enum.max(fn -> 0 end)

      max_id + 1
    else
      1
    end
  end

  # ---------------------------------------------------------------------------
  # Storage (formerly TeamStore)
  # ---------------------------------------------------------------------------

  defp store_create_task(team_name, attrs) when is_map(attrs) do
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

  defp store_update_task(team_name, task_id, changes) when is_map(changes) do
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

  defp store_delete_task(team_name, task_id) do
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

  defp task_sort_key(task) do
    case Integer.parse(task["id"] || "") do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_task_id_from_file(file) do
    case Integer.parse(String.replace_suffix(file, ".json", "")) do
      {n, ""} -> [n]
      _ -> []
    end
  end

  defp emit(signal, team_name, payload) do
    topic =
      case signal do
        :task_created -> "team.task.created"
        :task_updated -> "team.task.updated"
        :task_deleted -> "team.task.deleted"
      end

    Events.emit(
      Event.new(topic, team_name, Map.put(payload, :team_name, team_name), %{
        legacy_name: signal
      })
    )

    Events.emit(
      Event.new("team.tasks.updated", team_name, %{team_name: team_name}, %{
        legacy_name: :tasks_updated
      })
    )
  end
end
