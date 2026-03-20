defmodule Ichor.Factory.PipelineTask.Changes.SyncPipelineProcess do
  @moduledoc "After a pipeline task state transition, notifies the Runner GenServer to sync its state."

  use Ash.Resource.Change

  alias Ichor.Factory.Runner

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

  defp maybe_sync(run_id, task) do
    if Code.ensure_loaded?(Runner) and function_exported?(Runner, :sync_task, 2) do
      Runner.sync_task(run_id, task)
    end
  end
end
