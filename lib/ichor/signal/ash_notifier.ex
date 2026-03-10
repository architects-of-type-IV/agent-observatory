defmodule Ichor.Signal.AshNotifier do
  @moduledoc """
  Ash notifier that auto-emits signals on resource mutations.

  Attach to any Ash resource:

      use Ash.Resource, simple_notifiers: [Ichor.Signal.AshNotifier]

  Fires `Signal.emit/2` for mapped resource+action_type combinations.
  Unmapped resources are silently ignored (safe to attach broadly).
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, data: data}) do
    case signal_for(resource, action.type) do
      nil -> :ok
      {name, extract_fn} -> Ichor.Signal.emit(name, extract_fn.(data, action))
    end

    :ok
  end

  # ── Resource -> Signal mapping ──────────────────────────────────────

  defp signal_for(Ichor.Activity.Task, :create), do: {:task_created, &task_data/2}
  defp signal_for(Ichor.Activity.Task, :update), do: {:task_updated, &task_data/2}
  defp signal_for(Ichor.Activity.Task, :destroy), do: {:task_deleted, &task_data/2}
  defp signal_for(_, _), do: nil

  # ── Data extractors ─────────────────────────────────────────────────

  defp task_data(data, _action) do
    %{task: Map.take(data, [:id, :status, :subject, :team_name, :session_id])}
  end
end
