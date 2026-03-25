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
      nil ->
        :ok

      event ->
        Ingress.push(event)
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Pipeline
  # ---------------------------------------------------------------------------

  defp event_for(Pipeline, :create, data) do
    Event.new(
      "pipeline.run.created",
      data.id,
      %{run_id: data.id, label: data.label, source: data.source},
      %{resource: "Pipeline", action: :create}
    )
  end

  defp event_for(Pipeline, :complete, data) do
    Event.new(
      "pipeline.run.completed",
      data.id,
      %{run_id: data.id, label: data.label, source: data.source},
      %{resource: "Pipeline", action: :complete}
    )
  end

  defp event_for(Pipeline, :fail, data) do
    Event.new(
      "pipeline.run.failed",
      data.id,
      %{run_id: data.id, label: data.label, source: data.source},
      %{resource: "Pipeline", action: :fail}
    )
  end

  defp event_for(Pipeline, :archive, data) do
    Event.new(
      "pipeline.run.archived",
      data.id,
      %{run_id: data.id, label: data.label, source: data.source},
      %{resource: "Pipeline", action: :archive}
    )
  end

  # ---------------------------------------------------------------------------
  # PipelineTask
  # ---------------------------------------------------------------------------

  defp event_for(PipelineTask, :claim, data) do
    Event.new(
      "pipeline.task.claimed",
      data.run_id,
      %{
        task_id: data.id,
        run_id: data.run_id,
        external_id: data.external_id,
        subject: data.subject,
        status: data.status,
        owner: data.owner
      },
      %{resource: "PipelineTask", action: :claim}
    )
  end

  defp event_for(PipelineTask, :complete, data) do
    Event.new(
      "pipeline.task.completed",
      data.run_id,
      %{
        task_id: data.id,
        run_id: data.run_id,
        external_id: data.external_id,
        subject: data.subject,
        status: data.status,
        owner: data.owner
      },
      %{resource: "PipelineTask", action: :complete}
    )
  end

  defp event_for(PipelineTask, :fail, data) do
    Event.new(
      "pipeline.task.failed",
      data.run_id,
      %{
        task_id: data.id,
        run_id: data.run_id,
        external_id: data.external_id,
        subject: data.subject,
        status: data.status,
        owner: data.owner
      },
      %{resource: "PipelineTask", action: :fail}
    )
  end

  defp event_for(PipelineTask, :reset, data) do
    Event.new(
      "pipeline.task.reset",
      data.run_id,
      %{
        task_id: data.id,
        run_id: data.run_id,
        external_id: data.external_id,
        subject: data.subject,
        status: data.status,
        owner: data.owner
      },
      %{resource: "PipelineTask", action: :reset}
    )
  end

  # ---------------------------------------------------------------------------
  # Project
  # ---------------------------------------------------------------------------

  defp event_for(Project, :create, data) do
    Event.new(
      "project.created",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :create}
    )
  end

  defp event_for(Project, :advance, data) do
    Event.new(
      "project.stage.advanced",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :advance}
    )
  end

  defp event_for(Project, :pick_up, data) do
    Event.new(
      "project.claimed",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :pick_up}
    )
  end

  defp event_for(Project, :mark_compiled, data) do
    Event.new(
      "project.compiled",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :mark_compiled}
    )
  end

  defp event_for(Project, :mark_loaded, data) do
    Event.new(
      "project.plugin.loaded",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :mark_loaded}
    )
  end

  defp event_for(Project, :mark_failed, data) do
    Event.new(
      "project.failed",
      data.id,
      %{project_id: data.id, title: data.title},
      %{resource: "Project", action: :mark_failed}
    )
  end

  # ---------------------------------------------------------------------------
  # SettingsProject
  # ---------------------------------------------------------------------------

  defp event_for(SettingsProject, :create, data) do
    Event.new(
      "settings.project.created",
      data.id,
      %{project_id: data.id, name: data.name, is_active: data.is_active},
      %{resource: "SettingsProject", action: :create}
    )
  end

  defp event_for(SettingsProject, :update, data) do
    Event.new(
      "settings.project.updated",
      data.id,
      %{project_id: data.id, name: data.name, is_active: data.is_active},
      %{resource: "SettingsProject", action: :update}
    )
  end

  defp event_for(SettingsProject, :destroy, data) do
    Event.new(
      "settings.project.destroyed",
      data.id,
      %{project_id: data.id, name: data.name, is_active: data.is_active},
      %{resource: "SettingsProject", action: :destroy}
    )
  end

  # ---------------------------------------------------------------------------
  # WebhookDelivery
  # ---------------------------------------------------------------------------

  defp event_for(WebhookDelivery, :enqueue, data) do
    Event.new(
      "webhook.delivery.enqueued",
      data.id,
      %{
        delivery_id: data.id,
        agent_id: data.agent_id,
        target_url: data.target_url,
        status: data.status
      },
      %{resource: "WebhookDelivery", action: :enqueue}
    )
  end

  defp event_for(WebhookDelivery, :mark_delivered, data) do
    Event.new(
      "webhook.delivery.completed",
      data.id,
      %{
        delivery_id: data.id,
        agent_id: data.agent_id,
        target_url: data.target_url,
        status: data.status
      },
      %{resource: "WebhookDelivery", action: :mark_delivered}
    )
  end

  defp event_for(WebhookDelivery, :mark_dead, data) do
    Event.new(
      "webhook.delivery.failed",
      data.id,
      %{
        delivery_id: data.id,
        agent_id: data.agent_id,
        target_url: data.target_url,
        status: data.status
      },
      %{resource: "WebhookDelivery", action: :mark_dead}
    )
  end

  # ---------------------------------------------------------------------------
  # CronJob
  # ---------------------------------------------------------------------------

  defp event_for(CronJob, :schedule_once, data) do
    Event.new(
      "cron.job.scheduled",
      data.agent_id,
      %{job_id: data.id, agent_id: data.agent_id, next_fire_at: data.next_fire_at},
      %{resource: "CronJob", action: :schedule_once}
    )
  end

  defp event_for(CronJob, :reschedule, data) do
    Event.new(
      "cron.job.rescheduled",
      data.agent_id,
      %{job_id: data.id, agent_id: data.agent_id, next_fire_at: data.next_fire_at},
      %{resource: "CronJob", action: :reschedule}
    )
  end

  # ---------------------------------------------------------------------------
  # Catch-all: unmapped pairs are silently ignored
  # ---------------------------------------------------------------------------

  defp event_for(_resource, _action, _data), do: nil
end
