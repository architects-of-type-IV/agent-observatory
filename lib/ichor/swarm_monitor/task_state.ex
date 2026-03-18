defmodule Ichor.SwarmMonitor.TaskState do
  @moduledoc """
  Side-effectful task mutation helpers used by SwarmMonitor.
  """

  @claim_script Path.expand("~/.claude/skills/dag/scripts/claim-task.sh")

  @spec heal_task(String.t(), String.t()) :: :ok | {:error, term()}
  def heal_task(path, task_id), do: jq_update_task(path, task_id, "pending", "")

  @spec reassign_task(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def reassign_task(path, task_id, new_owner), do: jq_reassign_task(path, task_id, new_owner)

  @spec claim_task(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
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

  @spec update_task_status(String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, term()}
  def update_task_status(path, task_id, status, owner),
    do: jq_update_task(path, task_id, status, owner)

  defp jq_update_task(path, task_id, new_status, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    expr =
      ~s(if .id == "#{task_id}" then .status = "#{new_status}" | .owner = "#{new_owner}" | .updated = "#{now}" else . end)

    jq_in_place(path, expr)
  end

  defp jq_reassign_task(path, task_id, new_owner) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    expr =
      ~s(if .id == "#{task_id}" then .owner = "#{new_owner}" | .updated = "#{now}" else . end)

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
