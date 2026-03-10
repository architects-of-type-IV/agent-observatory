defmodule Ichor.Signals.FromAsh do
  @moduledoc """
  Ash notifier that translates resource mutations into signals.

  Attach to any Ash resource:

      use Ash.Resource, simple_notifiers: [Ichor.Signals.FromAsh]

  Ash notification shapes are translated into the Signals.Message envelope
  before the rest of the app sees them. Unmapped resources are silently ignored.
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, data: data}) do
    case signal_for(resource, action.type) do
      nil -> :ok
      {name, extract_fn} -> Ichor.Signals.emit(name, extract_fn.(data, action))
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
