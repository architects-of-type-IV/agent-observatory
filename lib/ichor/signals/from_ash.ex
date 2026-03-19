defmodule Ichor.Signals.FromAsh do
  @moduledoc """
  Ash notifier that translates resource mutations into signals.

  Attach to any Ash resource:

      use Ash.Resource, simple_notifiers: [Ichor.Signals.FromAsh]

  Maps `{resource, action.name}` to signal names. Unmapped actions are silently
  ignored. Fires post-commit so rolled-back mutations never emit signals.
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, data: data}) do
    case signal_for(resource, action.name) do
      nil -> :ok
      {name, extract_fn} -> Ichor.Signals.emit(name, extract_fn.(data, action))
    end

    :ok
  end

  defp signal_for(Ichor.Activity.Task, :create), do: {:task_created, &task_data/2}
  defp signal_for(Ichor.Activity.Task, :update), do: {:task_updated, &task_data/2}
  defp signal_for(Ichor.Activity.Task, :destroy), do: {:task_deleted, &task_data/2}

  defp signal_for(Ichor.Dag.Run, :create), do: {:dag_run_created, &run_data/2}
  defp signal_for(Ichor.Dag.Run, :complete), do: {:dag_run_completed, &run_data/2}
  defp signal_for(Ichor.Dag.Run, :fail), do: {:dag_run_completed, &run_data/2}
  defp signal_for(Ichor.Dag.Run, :archive), do: {:dag_run_archived, &run_archive_data/2}

  defp signal_for(Ichor.Genesis.Node, :create), do: {:genesis_node_created, &node_data/2}
  defp signal_for(Ichor.Genesis.Node, :advance), do: {:genesis_node_advanced, &node_data/2}

  defp signal_for(Ichor.Genesis.Adr, :create), do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Feature, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.UseCase, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Phase, :create), do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Section, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Task, :create), do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Subtask, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Checkpoint, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Genesis.Conversation, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Mes.Project, :pick_up), do: {:mes_project_picked_up, &project_data/2}
  defp signal_for(Ichor.Mes.Project, :mark_compiled), do: {:mes_project_compiled, &project_data/2}
  defp signal_for(Ichor.Mes.Project, :mark_loaded), do: {:mes_subsystem_loaded, &project_data/2}
  defp signal_for(Ichor.Mes.Project, :mark_failed), do: {:mes_project_failed, &project_data/2}

  defp signal_for(_, _), do: nil

  defp task_data(data, _action) do
    %{task: Map.take(data, [:id, :status, :subject, :team_name, :session_id])}
  end

  defp run_data(data, _action) do
    %{run_id: data.id, label: data.label, source: data.source, job_count: data.job_count}
  end

  defp run_archive_data(data, _action) do
    %{run_id: data.id, label: data.label, reason: "notifier"}
  end

  defp node_data(data, action) do
    %{id: data.id, node_id: data.id, title: data.title, type: action.name}
  end

  defp artifact_data(data, _action) do
    resource_type =
      data.__struct__
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_existing_atom()

    node_id = Map.get(data, :node_id) || Map.get(data, :genesis_node_id)
    %{id: data.id, node_id: node_id, type: resource_type}
  end

  defp project_data(data, _action) do
    %{project_id: data.id, title: data.title, session_id: Map.get(data, :picked_up_by)}
  end
end
