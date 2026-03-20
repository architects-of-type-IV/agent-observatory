defmodule Ichor.Projects.Job.Changes.SyncRunProcess do
  @moduledoc "After a job state transition, notifies the RunProcess GenServer to sync its state."

  use Ash.Resource.Change

  alias Ichor.Projects.RunProcess

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, result ->
      try do
        maybe_sync(result.run_id, result)
        {:ok, result}
      rescue
        _ -> {:ok, result}
      end
    end)
  end

  defp maybe_sync(run_id, job) do
    if Code.ensure_loaded?(RunProcess) and function_exported?(RunProcess, :sync_job, 2) do
      RunProcess.sync_job(run_id, job)
    end
  end
end
