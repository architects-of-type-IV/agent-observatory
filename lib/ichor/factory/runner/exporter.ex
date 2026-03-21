defmodule Ichor.Factory.Runner.Exporter do
  @moduledoc """
  File I/O and jq sync logic for pipeline task write-through.

  Syncs a pipeline task's status, owner, and updated timestamp back to the
  project's `tasks.jsonl` file on disk using a jq in-place update.
  """

  @doc """
  Syncs a task struct to the project's `tasks.jsonl` file.

  No-ops when `project_path` is nil or empty.
  """
  @spec sync_task_to_file(struct() | map(), String.t() | nil) :: :ok | {:error, term()}
  def sync_task_to_file(_task, nil), do: :ok
  def sync_task_to_file(_task, ""), do: :ok

  def sync_task_to_file(task, project_path) do
    tasks_path = Path.join(project_path, "tasks.jsonl")
    jq_update_item(tasks_path, task.external_id, to_string(task.status), task.owner || "")
  end

  defp jq_update_item(path, external_id, new_status, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    jq_expr =
      ~s(if .id == $eid then .status = $st | .owner = $ow | .updated = $ts else . end)

    jq_in_place(path, jq_expr, [
      "--arg",
      "eid",
      external_id,
      "--arg",
      "st",
      new_status,
      "--arg",
      "ow",
      new_owner,
      "--arg",
      "ts",
      now
    ])
  end

  defp jq_in_place(path, expr, extra_args) do
    tmp = path <> ".pipeline_tmp"

    case System.cmd("jq", ["-c"] ++ extra_args ++ [expr, path], stderr_to_stdout: true) do
      {output, 0} ->
        case File.write(tmp, output) do
          :ok ->
            File.rename!(tmp, path)
            :ok

          err ->
            File.rm(tmp)
            err
        end

      {err, _} ->
        {:error, err}
    end
  end
end
