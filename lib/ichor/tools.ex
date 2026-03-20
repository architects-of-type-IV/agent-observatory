defmodule Ichor.Tools do
  @moduledoc """
  Ash Domain: MCP tool surfaces for agents and the Archon.

  Capability-based organization. Exposure scoped per MCP endpoint
  (/mcp/agent, /mcp/archon) via router tool lists.
  """
  use Ash.Domain, extensions: [AshAi], validate_config_inclusion?: true

  alias Ichor.Factory.{Floor, Project}
  alias Ichor.Signals.Mailbox
  alias Ichor.Tools.AgentMemory
  alias Ichor.Tools.RuntimeOps

  alias Ichor.Tools.Archon.Memory, as: ArchonMemory

  resources do
    # Agent tools (5)
    resource(RuntimeOps)
    resource(AgentMemory)
    # Archon-only tools (1)
    resource(ArchonMemory)
  end

  tools do
    # Inbox (agent-facing)
    tool(:check_inbox, RuntimeOps, :check_inbox)
    tool(:acknowledge_message, RuntimeOps, :acknowledge_message)
    tool(:send_message, RuntimeOps, :agent_send_message)
    # Tasks
    tool(:get_tasks, Floor, :get_tasks)
    tool(:update_task_status, Floor, :update_task_status)
    # Core memory
    tool(:read_memory, AgentMemory, :read_memory)
    tool(:memory_replace, AgentMemory, :memory_replace)
    tool(:memory_insert, AgentMemory, :memory_insert)
    tool(:memory_rethink, AgentMemory, :memory_rethink)
    # Recall
    tool(:conversation_search, AgentMemory, :conversation_search)
    tool(:conversation_search_date, AgentMemory, :conversation_search_date)
    # Archival
    tool(:archival_memory_insert, AgentMemory, :archival_memory_insert)
    tool(:archival_memory_search, AgentMemory, :archival_memory_search)
    # Agent management
    tool(:create_agent, AgentMemory, :create_agent)
    tool(:list_agents, AgentMemory, :list_registered_agents)
    # Fleet spawning (agent-facing)
    tool(:spawn_agent, RuntimeOps, :spawn_agent)
    tool(:stop_agent, RuntimeOps, :stop_agent)
    # Project planning
    tool(:create_project_draft, Project, :create_project_draft)
    tool(:advance_project, Project, :advance_project)
    tool(:list_project_overviews, Project, :list_project_overviews)
    tool(:get_project_overview, Project, :get_project_overview)
    tool(:gate_check, Project, :gate_check)
    # Project artifacts
    tool(:create_adr, Project, :create_adr)
    tool(:update_adr, Project, :update_adr)
    tool(:list_adrs, Project, :list_adrs)
    tool(:create_feature, Project, :create_feature)
    tool(:list_features, Project, :list_features)
    tool(:create_use_case, Project, :create_use_case)
    tool(:list_use_cases, Project, :list_use_cases)
    # Project gates
    tool(:create_checkpoint, Project, :create_checkpoint)
    tool(:create_conversation, Project, :create_conversation)
    tool(:list_conversations, Project, :list_conversations)
    # Project roadmap (Mode C)
    tool(:create_phase, Project, :create_phase)
    tool(:create_section, Project, :create_section)
    tool(:create_task, Project, :create_task)
    tool(:create_subtask, Project, :create_subtask)
    tool(:list_phases, Project, :list_phases)
    # DAG execution
    tool(:next_tasks, Ichor.Factory.PipelineTask, :next_tasks)
    tool(:claim_task, Ichor.Factory.PipelineTask, :claim_task)
    tool(:complete_task, Ichor.Factory.PipelineTask, :complete_task)
    tool(:fail_task, Ichor.Factory.PipelineTask, :fail_task)
    tool(:get_run_status, Ichor.Factory.Pipeline, :get_run_status)
    tool(:load_jsonl, Ichor.Factory.Pipeline, :load_jsonl)
    tool(:export_jsonl, Ichor.Factory.Pipeline, :export_jsonl)
    # Fleet observation (Archon)
    tool(:list_archon_agents, RuntimeOps, :list_live_agents)
    tool(:agent_status, RuntimeOps, :agent_status)
    tool(:list_teams, RuntimeOps, :list_teams)
    # Fleet control (Archon)
    tool(:spawn_archon_agent, RuntimeOps, :spawn_archon_agent)
    tool(:stop_archon_agent, RuntimeOps, :stop_agent)
    tool(:pause_agent, RuntimeOps, :pause_agent)
    tool(:resume_agent, RuntimeOps, :resume_agent)
    tool(:sweep, RuntimeOps, :sweep)
    # Messaging (Archon)
    tool(:recent_messages, RuntimeOps, :recent_messages)
    tool(:archon_send_message, RuntimeOps, :operator_send_message)
    # System (Archon)
    tool(:system_health, RuntimeOps, :system_health)
    tool(:tmux_sessions, RuntimeOps, :tmux_sessions)
    tool(:manager_snapshot, RuntimeOps, :manager_snapshot)
    tool(:attention_queue, RuntimeOps, :attention_queue)
    # Events & tasks (Archon)
    tool(:agent_events, RuntimeOps, :agent_events)
    tool(:fleet_tasks, RuntimeOps, :fleet_tasks)
    # Memory (Archon)
    tool(:search_memory, ArchonMemory, :search_memory)
    tool(:remember, ArchonMemory, :remember)
    tool(:query_memory, ArchonMemory, :query_memory)
    # MES floor management (Archon)
    tool(:list_projects, Project, :list_projects)
    tool(:create_project, Project, :create_project)
    tool(:check_operator_inbox, Mailbox, :check_operator_inbox)
    tool(:mes_status, Floor, :mes_status)
    tool(:cleanup_mes, Floor, :cleanup_mes)
  end
end
