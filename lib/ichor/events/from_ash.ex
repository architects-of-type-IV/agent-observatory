defmodule Ichor.Events.FromAsh do
  @moduledoc """
  Ash notifier that emits domain fact Events directly into the GenStage pipeline.

  Attach to any Ash resource alongside or instead of `Ichor.Signals.FromAsh`:

      use Ash.Resource, simple_notifiers: [Ichor.Events.FromAsh]

  Maps `{resource, action.name}` to domain fact topics and emits `%Event{}`
  via `Ichor.Events.Ingress.push/1`. Fires post-commit so rolled-back mutations
  never emit events. Unmapped actions are silently ignored.
  """

  use Ash.Notifier

  alias Ichor.Events.{Event, Ingress}

  @impl true
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, data: data}) do
    case event_for(resource, action.name) do
      nil ->
        :ok

      {topic, key, extract_fn} ->
        event =
          Event.new(topic, key.(data), extract_fn.(data, action), %{
            resource: inspect(resource),
            action: action.name,
            source: :ash_notifier
          })

        Ingress.push(event)
    end

    :ok
  end

  # -- Pipeline --

  defp event_for(Ichor.Factory.Pipeline, :create),
    do: {"pipeline.run.created", &run_key/1, &run_data/2}

  defp event_for(Ichor.Factory.Pipeline, :complete),
    do: {"pipeline.run.completed", &run_key/1, &run_data/2}

  defp event_for(Ichor.Factory.Pipeline, :fail),
    do: {"pipeline.run.completed", &run_key/1, &run_data/2}

  defp event_for(Ichor.Factory.Pipeline, :archive),
    do: {"pipeline.run.archived", &run_key/1, &run_archive_data/2}

  # -- PipelineTask --

  defp event_for(Ichor.Factory.PipelineTask, :claim),
    do: {"pipeline.task.claimed", &task_key/1, &task_data/2}

  defp event_for(Ichor.Factory.PipelineTask, :complete),
    do: {"pipeline.task.completed", &task_key/1, &task_data/2}

  defp event_for(Ichor.Factory.PipelineTask, :fail),
    do: {"pipeline.task.failed", &task_key/1, &task_data/2}

  defp event_for(Ichor.Factory.PipelineTask, :reset),
    do: {"pipeline.task.reset", &task_key/1, &task_data/2}

  # -- Project --

  defp event_for(Ichor.Factory.Project, :create),
    do: {"planning.project.created", &project_key/1, &project_data/2}

  defp event_for(Ichor.Factory.Project, :advance),
    do: {"planning.project.advanced", &project_key/1, &project_data/2}

  defp event_for(Ichor.Factory.Project, :pick_up),
    do: {"mes.project.claimed", &project_key/1, &project_data/2}

  defp event_for(Ichor.Factory.Project, :mark_compiled),
    do: {"mes.project.compiled", &project_key/1, &project_data/2}

  defp event_for(Ichor.Factory.Project, :mark_loaded),
    do: {"mes.plugin.loaded", &project_key/1, &project_data/2}

  defp event_for(Ichor.Factory.Project, :mark_failed),
    do: {"mes.project.failed", &project_key/1, &project_data/2}

  # -- WebhookDelivery --

  defp event_for(Ichor.Infrastructure.WebhookDelivery, :enqueue),
    do: {"gateway.webhook.enqueued", &webhook_key/1, &webhook_data/2}

  defp event_for(Ichor.Infrastructure.WebhookDelivery, :mark_delivered),
    do: {"gateway.webhook.delivered", &webhook_key/1, &webhook_data/2}

  defp event_for(Ichor.Infrastructure.WebhookDelivery, :mark_dead),
    do: {"gateway.webhook.dead_lettered", &webhook_key/1, &webhook_data/2}

  # -- HITLInterventionEvent --

  defp event_for(Ichor.Signals.HITLInterventionEvent, :record),
    do: {"hitl.operator.intervention_recorded", &hitl_key/1, &hitl_data/2}

  # -- CronJob --

  defp event_for(Ichor.Factory.CronJob, :schedule_once),
    do: {"gateway.cron.scheduled", &cron_key/1, &cron_data/2}

  defp event_for(Ichor.Factory.CronJob, :reschedule),
    do: {"gateway.cron.rescheduled", &cron_key/1, &cron_data/2}

  # -- SettingsProject --

  defp event_for(Ichor.Settings.SettingsProject, :create),
    do: {"settings.project.created", &settings_key/1, &settings_project_data/2}

  defp event_for(Ichor.Settings.SettingsProject, :update),
    do: {"settings.project.updated", &settings_key/1, &settings_project_data/2}

  defp event_for(Ichor.Settings.SettingsProject, :destroy),
    do: {"settings.project.deleted", &settings_key/1, &settings_project_data/2}

  defp event_for(_, _), do: nil

  # -- Key extractors --

  defp run_key(data), do: data.id
  defp task_key(data), do: data.run_id
  defp project_key(data), do: data.id
  defp webhook_key(data), do: data.id
  defp hitl_key(data), do: data.session_id
  defp cron_key(data), do: data.agent_id
  defp settings_key(data), do: data.id

  # -- Data extractors --

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
    %{run_id: data.id, label: data.label, source: data.source}
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

  defp settings_project_data(data, _action) do
    %{project_id: data.id, name: data.name, is_active: data.is_active}
  end
end
