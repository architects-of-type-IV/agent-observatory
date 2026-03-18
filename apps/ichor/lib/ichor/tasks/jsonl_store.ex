defmodule Ichor.Tasks.JsonlStore do
  @moduledoc """
  In-place `tasks.jsonl` mutation helpers.
  """

  @claim_script Path.expand("~/.claude/skills/dag/scripts/claim-task.sh")

  def heal_task(path, task_id), do: update_task_status(path, task_id, "pending", "")

  def reassign_task(path, task_id, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    expr =
      ~s(if .id == "#{task_id}" then .owner = "#{new_owner}" | .updated = "#{now}" else . end)

    jq_in_place(path, expr)
  end

  def claim_task(task_id, agent_name, path) do
    case System.cmd("bash", [@claim_script, task_id, agent_name, path],
           stderr_to_stdout: true,
           env: []
         ) do
      {output, 0} ->
        if String.contains?(output, "CLAIMED"), do: :ok, else: {:error, String.trim(output)}

      {output, _} ->
        {:error, String.trim(output)}
    end
  end

  def update_task_status(path, task_id, status, owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    expr =
      ~s(if .id == "#{task_id}" then .status = "#{status}" | .owner = "#{owner}" | .updated = "#{now}" else . end)

    jq_in_place(path, expr)
  end

  defp jq_in_place(path, expr) do
    tmp = path <> ".tmp"

    case System.cmd("jq", ["-c", expr, path], stderr_to_stdout: true) do
      {output, 0} ->
        case File.write(tmp, output) do
          :ok ->
            File.rename!(tmp, path)
            :ok

          err ->
            File.rm(tmp)
            err
        end

      {output, _} ->
        {:error, output}
    end
  end
end
