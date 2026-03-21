defmodule Ichor.Factory do
  @moduledoc """
  Ash Domain: MES planning and pipeline execution.

  Owns MES projects, planning artifacts, pipelines, pipeline tasks, and the execution
  lifecycle that turns planned work into wave-based delivery.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Factory.Project)
    resource(Ichor.Factory.Floor)
    resource(Ichor.Factory.Pipeline)
    resource(Ichor.Factory.PipelineTask)
    resource(Ichor.Factory.CronJob)
  end

  tools do
    tool(:get_tasks, Ichor.Factory.Floor, :get_tasks)
    tool(:update_task_status, Ichor.Factory.Floor, :update_task_status)
    tool(:mes_status, Ichor.Factory.Floor, :mes_status)
    tool(:cleanup_mes, Ichor.Factory.Floor, :cleanup_mes)
    tool(:fleet_tasks, Ichor.Factory.Floor, :fleet_tasks)
    tool(:create_project_draft, Ichor.Factory.Project, :create_project_draft)
    tool(:advance_project, Ichor.Factory.Project, :advance_project)
    tool(:list_project_overviews, Ichor.Factory.Project, :list_project_overviews)
    tool(:get_project_overview, Ichor.Factory.Project, :get_project_overview)
    tool(:gate_check, Ichor.Factory.Project, :gate_check)
    tool(:create_adr, Ichor.Factory.Project, :create_adr)
    tool(:update_adr, Ichor.Factory.Project, :update_adr)
    tool(:list_adrs, Ichor.Factory.Project, :list_adrs)
    tool(:create_feature, Ichor.Factory.Project, :create_feature)
    tool(:list_features, Ichor.Factory.Project, :list_features)
    tool(:create_use_case, Ichor.Factory.Project, :create_use_case)
    tool(:list_use_cases, Ichor.Factory.Project, :list_use_cases)
    tool(:create_checkpoint, Ichor.Factory.Project, :create_checkpoint)
    tool(:create_conversation, Ichor.Factory.Project, :create_conversation)
    tool(:list_conversations, Ichor.Factory.Project, :list_conversations)
    tool(:create_phase, Ichor.Factory.Project, :create_phase)
    tool(:create_section, Ichor.Factory.Project, :create_section)
    tool(:create_task, Ichor.Factory.Project, :create_task)
    tool(:create_subtask, Ichor.Factory.Project, :create_subtask)
    tool(:list_phases, Ichor.Factory.Project, :list_phases)
    tool(:list_projects, Ichor.Factory.Project, :list_projects)
    tool(:create_project, Ichor.Factory.Project, :create_project)
    tool(:next_tasks, Ichor.Factory.PipelineTask, :next_tasks)
    tool(:claim_task, Ichor.Factory.PipelineTask, :claim_task)
    tool(:complete_task, Ichor.Factory.PipelineTask, :complete_task)
    tool(:fail_task, Ichor.Factory.PipelineTask, :fail_task)
    tool(:get_run_status, Ichor.Factory.Pipeline, :get_run_status)
    tool(:load_jsonl, Ichor.Factory.Pipeline, :load_jsonl)
    tool(:export_jsonl, Ichor.Factory.Pipeline, :export_jsonl)
  end
end
