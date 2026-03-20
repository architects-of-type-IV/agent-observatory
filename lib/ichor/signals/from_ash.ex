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

  defp signal_for(Ichor.Factory.Pipeline, :create), do: {:pipeline_created, &run_data/2}
  defp signal_for(Ichor.Factory.Pipeline, :complete), do: {:pipeline_completed, &run_data/2}
  defp signal_for(Ichor.Factory.Pipeline, :fail), do: {:pipeline_completed, &run_data/2}
  defp signal_for(Ichor.Factory.Pipeline, :archive), do: {:pipeline_archived, &run_archive_data/2}

  defp signal_for(Ichor.Factory.PipelineTask, :claim), do: {:pipeline_task_claimed, &task_data/2}

  defp signal_for(Ichor.Factory.PipelineTask, :complete),
    do: {:pipeline_task_completed, &task_data/2}

  defp signal_for(Ichor.Factory.PipelineTask, :fail), do: {:pipeline_task_failed, &task_data/2}
  defp signal_for(Ichor.Factory.PipelineTask, :reset), do: {:pipeline_task_reset, &task_data/2}

  defp signal_for(Ichor.Factory.Project, :create), do: {:project_created, &project_data/2}
  defp signal_for(Ichor.Factory.Project, :advance), do: {:project_advanced, &project_data/2}

  defp signal_for(Ichor.Factory.Project, :pick_up), do: {:mes_project_picked_up, &project_data/2}

  defp signal_for(Ichor.Factory.Project, :mark_compiled),
    do: {:mes_project_compiled, &project_data/2}

  defp signal_for(Ichor.Factory.Project, :mark_loaded),
    do: {:mes_plugin_loaded, &project_data/2}

  defp signal_for(Ichor.Factory.Project, :mark_failed),
    do: {:mes_project_failed, &project_data/2}

  defp signal_for(Ichor.Infrastructure.WebhookDelivery, :enqueue),
    do: {:webhook_delivery_enqueued, &webhook_data/2}

  defp signal_for(Ichor.Infrastructure.WebhookDelivery, :mark_delivered),
    do: {:webhook_delivery_delivered, &webhook_data/2}

  defp signal_for(Ichor.Infrastructure.WebhookDelivery, :mark_dead),
    do: {:dead_letter, &webhook_data/2}

  defp signal_for(Ichor.Observability.HITLInterventionEvent, :record),
    do: {:hitl_intervention_recorded, &hitl_data/2}

  defp signal_for(Ichor.Infrastructure.CronJob, :schedule_once),
    do: {:cron_job_scheduled, &cron_data/2}

  defp signal_for(Ichor.Infrastructure.CronJob, :reschedule),
    do: {:cron_job_rescheduled, &cron_data/2}

  defp signal_for(_, _), do: nil

  defp task_data(data, _action) do
    %{
      task_id: data.id,
      run_id: data.run_id,
      external_id: data.external_id,
      subject: data.subject,
      status: data.status,
      owner: data.owner
    }
  end

  defp run_data(data, _action) do
    %{run_id: data.id, label: data.label, source: data.source, task_count: data.task_count}
  end

  defp run_archive_data(data, _action) do
    %{run_id: data.id, label: data.label, reason: "notifier"}
  end

  defp project_data(data, %{name: name}) when name in [:create, :advance] do
    %{id: data.id, project_id: data.id, title: data.title, type: name}
  end

  defp project_data(data, _action) do
    %{
      project_id: data.id,
      title: data.title,
      plugin: Map.get(data, :plugin),
      session_id: Map.get(data, :picked_up_by)
    }
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
