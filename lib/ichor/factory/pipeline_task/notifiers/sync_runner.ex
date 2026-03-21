defmodule Ichor.Factory.PipelineTask.Notifiers.SyncRunner do
  @moduledoc "Notifies Runner GenServer after pipeline task state transitions."

  use Ash.Notifier

  alias Ichor.Factory.Runner

  @impl true
  def notify(%Ash.Notifier.Notification{resource: Ichor.Factory.PipelineTask} = notification) do
    if notification.action.name in [:claim, :complete, :fail, :reset] do
      maybe_sync(notification.data.run_id, notification.data)
    end

    :ok
  end

  defp maybe_sync(run_id, task) do
    if Code.ensure_loaded?(Runner) and function_exported?(Runner, :sync_task, 2) do
      try do
        Runner.sync_task(run_id, task)
      rescue
        _ -> :ok
      end
    end
  end
end
