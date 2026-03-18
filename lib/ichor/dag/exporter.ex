defmodule Ichor.Dag.Exporter do
  @moduledoc """
  Exports Dag.Job records to tasks.jsonl format.

  Three modes:
  - `to_file/2` -- full export of all jobs for a run
  - `to_string/1` -- returns JSONL string (for MCP tool response)
  - `sync_to_file/2` -- single-item write-through via jq atomic swap
    Called by RunProcess (serialized) after job state mutations.
    No-op if run has no project_path.
  """

  alias Ichor.Dag.Job

  @spec to_file(String.t(), String.t()) :: :ok | {:error, term()}
  def to_file(run_id, output_path) do
    with {:ok, jobs} <- Job.by_run(run_id) do
      jsonl = Enum.map_join(jobs, "\n", &job_to_jsonl/1)
      File.write!(output_path, jsonl <> "\n")
      :ok
    end
  end

  @spec to_jsonl(String.t()) :: {:ok, String.t()} | {:error, term()}
  def to_jsonl(run_id) do
    with {:ok, jobs} <- Job.by_run(run_id) do
      {:ok, Enum.map_join(jobs, "\n", &job_to_jsonl/1)}
    end
  end

  @spec sync_to_file(Ichor.Dag.Job.t(), String.t() | nil) :: :ok | {:error, term()}
  def sync_to_file(_job, nil), do: :ok
  def sync_to_file(_job, ""), do: :ok

  def sync_to_file(job, project_path) do
    tasks_path = Path.join(project_path, "tasks.jsonl")
    jq_update_item(tasks_path, job.external_id, to_string(job.status), job.owner || "")
  end

  # ── Private ──────────────────────────────────────────────────────

  defp job_to_jsonl(job) do
    %{
      "id" => job.external_id,
      "status" => Kernel.to_string(job.status),
      "subject" => job.subject,
      "description" => job.description,
      "goal" => job.goal,
      "files" => job.allowed_files,
      "steps" => job.steps,
      "done_when" => job.done_when,
      "blocked_by" => job.blocked_by,
      "owner" => job.owner || "",
      "priority" => Kernel.to_string(job.priority),
      "acceptance_criteria" => job.acceptance_criteria,
      "feature" => job.phase_label,
      "tags" => job.tags,
      "notes" => job.notes || "",
      "wave" => job.wave,
      "created" => format_dt(job.inserted_at),
      "updated" => format_dt(job.updated_at)
    }
    |> Jason.encode!()
  end

  defp format_dt(nil), do: ""
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%dT%H:%M:%SZ")
  defp format_dt(_), do: ""

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
    tmp = path <> ".dag_tmp"

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
