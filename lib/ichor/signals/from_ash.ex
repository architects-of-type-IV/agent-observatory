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

  defp signal_for(Ichor.Projects.Run, :create), do: {:dag_run_created, &run_data/2}
  defp signal_for(Ichor.Projects.Run, :complete), do: {:dag_run_completed, &run_data/2}
  defp signal_for(Ichor.Projects.Run, :fail), do: {:dag_run_completed, &run_data/2}
  defp signal_for(Ichor.Projects.Run, :archive), do: {:dag_run_archived, &run_archive_data/2}

  defp signal_for(Ichor.Projects.Node, :create), do: {:genesis_node_created, &node_data/2}
  defp signal_for(Ichor.Projects.Node, :advance), do: {:genesis_node_advanced, &node_data/2}

  defp signal_for(Ichor.Projects.Adr, :create), do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Feature, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.UseCase, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Phase, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Section, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.RoadmapTask, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Subtask, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Checkpoint, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Conversation, :create),
    do: {:genesis_artifact_created, &artifact_data/2}

  defp signal_for(Ichor.Projects.Project, :pick_up), do: {:mes_project_picked_up, &project_data/2}

  defp signal_for(Ichor.Projects.Project, :mark_compiled),
    do: {:mes_project_compiled, &project_data/2}

  defp signal_for(Ichor.Projects.Project, :mark_loaded),
    do: {:mes_subsystem_loaded, &project_data/2}

  defp signal_for(Ichor.Projects.Project, :mark_failed),
    do: {:mes_project_failed, &project_data/2}

  defp signal_for(Ichor.Gateway.WebhookDelivery, :enqueue),
    do: {:webhook_delivery_enqueued, &webhook_data/2}

  defp signal_for(Ichor.Gateway.WebhookDelivery, :mark_delivered),
    do: {:webhook_delivery_delivered, &webhook_data/2}

  defp signal_for(Ichor.Gateway.WebhookDelivery, :mark_dead),
    do: {:dead_letter, &webhook_data/2}

  defp signal_for(Ichor.Gateway.HITLInterventionEvent, :record),
    do: {:hitl_intervention_recorded, &hitl_data/2}

  defp signal_for(Ichor.Gateway.CronJob, :schedule_once),
    do: {:cron_job_scheduled, &cron_data/2}

  defp signal_for(Ichor.Gateway.CronJob, :reschedule),
    do: {:cron_job_rescheduled, &cron_data/2}

  defp signal_for(_, _), do: nil

  defp run_data(data, _action) do
    %{run_id: data.id, label: data.label, source: data.source, job_count: data.job_count}
  end

  defp run_archive_data(data, _action) do
    %{run_id: data.id, label: data.label, reason: "notifier"}
  end

  defp node_data(data, action) do
    %{id: data.id, node_id: data.id, title: data.title, type: action.name}
  end

  @artifact_type_map %{
    Ichor.Projects.Adr => :adr,
    Ichor.Projects.Feature => :feature,
    Ichor.Projects.UseCase => :use_case,
    Ichor.Projects.Phase => :phase,
    Ichor.Projects.Section => :section,
    Ichor.Projects.RoadmapTask => :roadmap_task,
    Ichor.Projects.Subtask => :subtask,
    Ichor.Projects.Checkpoint => :checkpoint,
    Ichor.Projects.Conversation => :conversation
  }

  defp artifact_data(data, _action) do
    resource_type = Map.get(@artifact_type_map, data.__struct__, :unknown)
    node_id = Map.get(data, :node_id) || Map.get(data, :genesis_node_id)
    %{id: data.id, node_id: node_id, type: resource_type}
  end

  defp project_data(data, _action) do
    %{project_id: data.id, title: data.title, session_id: Map.get(data, :picked_up_by)}
  end

  defp webhook_data(data, _action) do
    %{
      delivery_id: data.id,
      agent_id: data.agent_id,
      target_url: data.target_url,
      status: data.status,
      attempt_count: data.attempt_count
    }
  end

  defp hitl_data(data, _action) do
    %{
      event_id: data.id,
      session_id: data.session_id,
      agent_id: data.agent_id,
      operator_id: data.operator_id,
      action: data.action,
      details: data.details
    }
  end

  defp cron_data(data, _action) do
    %{job_id: data.id, agent_id: data.agent_id, next_fire_at: data.next_fire_at}
  end
end
