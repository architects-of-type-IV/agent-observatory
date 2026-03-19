defmodule Ichor.Dag do
  @moduledoc """
  Ash Domain: DAG Execution.

  Sovereign task execution control plane. Manages parallel agent work
  through directed acyclic graphs of claimable jobs with dependency chains.

  Separate from Genesis (planning) -- they relate via node_id but are
  independent bounded contexts.
  """

  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Dag.Job
  alias Ichor.Dag.Run

  resources do
    resource(Ichor.Dag.Run)
    resource(Ichor.Dag.Job)
  end

  @spec get_run(String.t()) :: {:ok, Run.t()} | {:error, term()}
  def get_run(id), do: Run.get(id)

  @spec active_runs() :: list(Run.t())
  def active_runs, do: Run.active!()

  @spec runs_by_node(String.t()) :: list(Run.t())
  def runs_by_node(node_id), do: Run.by_node!(node_id)

  @spec runs_by_path(String.t()) :: list(Run.t())
  def runs_by_path(project_path), do: Run.by_path!(project_path)

  @spec jobs_for_run(String.t()) :: list(Job.t())
  def jobs_for_run(run_id), do: Job.by_run!(run_id)

  @spec fetch_jobs_for_run(String.t()) :: {:ok, list(Job.t())} | {:error, term()}
  def fetch_jobs_for_run(run_id), do: Job.by_run(run_id)
end
