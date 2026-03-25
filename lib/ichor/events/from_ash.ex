defmodule Ichor.Events.FromAsh do
  @moduledoc """
  Ash notifier that bridges resource mutations into the `%Event{}` pipeline.

  Called by Ash after every committed action on resources that declare
  `simple_notifiers: [Ichor.Events.FromAsh]`. Maps `{resource, action_name}`
  to a dot-delimited topic string, builds an `%Event{}`, and pushes it to
  `Ichor.Events.Ingress`. Unmapped pairs are silently dropped.
  """

  use Ash.Notifier

  alias Ichor.Events.{Event, Ingress}
  alias Ichor.Factory.{CronJob, Pipeline, PipelineTask, Project}
  alias Ichor.Infrastructure.WebhookDelivery
  alias Ichor.Settings.SettingsProject

  @impl true
  @spec notify(Ash.Notifier.Notification.t()) :: :ok
  def notify(%Ash.Notifier.Notification{resource: resource, action: action, data: data}) do
    case event_for(resource, action.name, data) do
      nil -> :ok
      event -> Ingress.push(event)
    end

    :ok
  end

  # ── Pipeline (same payload shape across 4 actions) ──────────────

  @pipeline_topics %{
    create: "pipeline.run.created",
    complete: "pipeline.run.completed",
    fail: "pipeline.run.failed",
    archive: "pipeline.run.archived"
  }

  defp event_for(Pipeline, action, data) when is_map_key(@pipeline_topics, action) do
    Event.new(
      @pipeline_topics[action],
      data.id,
      %{run_id: data.id, label: data.label, source: data.source},
      %{resource: "Pipeline", action: action}
    )
  end

  # ── PipelineTask (same payload shape across 4 actions) ──────────

  @task_topics %{
    claim: "pipeline.task.claimed",
    complete: "pipeline.task.completed",
    fail: "pipeline.task.failed",
    reset: "pipeline.task.reset"
  }

  defp event_for(PipelineTask, action, data) when is_map_key(@task_topics, action) do
    Event.new(
      @task_topics[action],
      data.run_id,
      %{
        task_id: data.id,
        run_id: data.run_id,
        external_id: data.external_id,
        subject: data.subject,
        status: data.status,
        owner: data.owner
      },
      %{resource: "PipelineTask", action: action}
    )
  end

  # ── Project (same payload shape across 6 actions) ───────────────

  @project_topics %{
    create: "project.created",
    advance: "project.stage.advanced",
    pick_up: "project.claimed",
    mark_compiled: "project.compiled",
    mark_loaded: "project.plugin.loaded",
    mark_failed: "project.failed"
  }

  defp event_for(Project, action, data) when is_map_key(@project_topics, action) do
    Event.new(@project_topics[action], data.id, %{project_id: data.id, title: data.title}, %{
      resource: "Project",
      action: action
    })
  end

  # ── SettingsProject (same payload shape across 3 actions) ───────

  @settings_topics %{
    create: "settings.project.created",
    update: "settings.project.updated",
    destroy: "settings.project.destroyed"
  }

  defp event_for(SettingsProject, action, data) when is_map_key(@settings_topics, action) do
    Event.new(
      @settings_topics[action],
      data.id,
      %{project_id: data.id, name: data.name, is_active: data.is_active},
      %{resource: "SettingsProject", action: action}
    )
  end

  # ── WebhookDelivery (same payload shape across 3 actions) ───────

  @webhook_topics %{
    enqueue: "webhook.delivery.enqueued",
    mark_delivered: "webhook.delivery.completed",
    mark_dead: "webhook.delivery.failed"
  }

  defp event_for(WebhookDelivery, action, data) when is_map_key(@webhook_topics, action) do
    Event.new(
      @webhook_topics[action],
      data.id,
      %{
        delivery_id: data.id,
        agent_id: data.agent_id,
        target_url: data.target_url,
        status: data.status
      },
      %{resource: "WebhookDelivery", action: action}
    )
  end

  # ── CronJob ─────────────────────────────────────────────────────

  @cron_topics %{
    schedule_once: "cron.job.scheduled",
    reschedule: "cron.job.rescheduled"
  }

  defp event_for(CronJob, action, data) when is_map_key(@cron_topics, action) do
    Event.new(
      @cron_topics[action],
      data.agent_id,
      %{job_id: data.id, agent_id: data.agent_id, next_fire_at: data.next_fire_at},
      %{resource: "CronJob", action: action}
    )
  end

  # ── Catch-all: unmapped pairs silently ignored ──────────────────

  defp event_for(_resource, _action, _data), do: nil
end
