defmodule Ichor.Dag.Handoff do
  @moduledoc """
  Pure swarm handoff packaging for DAG jobs.
  """

  @spec package_jobs(String.t(), [map()]) :: map()
  def package_jobs(run_id, jobs) do
    normalized =
      jobs
      |> Enum.sort_by(&{&1.wave || 0, &1.external_id})
      |> Enum.map(&job_packet/1)

    %{
      run_id: run_id,
      waves: Enum.group_by(normalized, & &1.wave),
      jobs: normalized
    }
  end

  @spec job_packet(map()) :: map()
  def job_packet(job) do
    %{
      id: job.id,
      external_id: job.external_id,
      wave: job.wave || 0,
      subject: job.subject,
      description: job.description,
      goal: job.goal,
      allowed_files: job.allowed_files || [],
      steps: job.steps || [],
      done_when: job.done_when,
      blocked_by: job.blocked_by || [],
      owner: job.owner,
      priority: job.priority,
      acceptance_criteria: job.acceptance_criteria || [],
      phase_label: job.phase_label,
      tags: job.tags || [],
      notes: job.notes
    }
  end
end
