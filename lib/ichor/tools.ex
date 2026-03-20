defmodule Ichor.Tools do
  @moduledoc """
  Ash Domain: MCP tool surfaces for agents and the Archon.

  Capability-based organization. Exposure scoped per MCP endpoint
  (/mcp/agent, /mcp/archon) via router tool lists.
  """
  use Ash.Domain, extensions: [AshAi], validate_config_inclusion?: true

  alias Ichor.Tools.Agent.GenesisArtifacts
  alias Ichor.Tools.Agent.GenesisGates
  alias Ichor.Tools.Agent.GenesisNodes
  alias Ichor.Tools.Agent.GenesisRoadmap
  alias Ichor.Tools.AgentMemory
  alias Ichor.Tools.ProjectExecution
  alias Ichor.Tools.RuntimeOps

  alias Ichor.Tools.Archon.Memory, as: ArchonMemory

  resources do
    # Agent tools (7)
    resource(RuntimeOps)
    resource(AgentMemory)
    resource(GenesisNodes)
    resource(GenesisArtifacts)
    resource(GenesisGates)
    resource(GenesisRoadmap)
    resource(ProjectExecution)
    # Archon-only tools (1)
    resource(ArchonMemory)
  end

  tools do
    # Inbox (agent-facing)
    tool(:check_inbox, RuntimeOps, :check_inbox)
    tool(:acknowledge_message, RuntimeOps, :acknowledge_message)
    tool(:send_message, RuntimeOps, :agent_send_message)
    # Tasks
    tool(:get_tasks, ProjectExecution, :get_tasks)
    tool(:update_task_status, ProjectExecution, :update_task_status)
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
    # Genesis nodes
    tool(:create_genesis_node, GenesisNodes, :create_genesis_node)
    tool(:advance_node, GenesisNodes, :advance_node)
    tool(:list_genesis_nodes, GenesisNodes, :list_genesis_nodes)
    tool(:get_genesis_node, GenesisNodes, :get_genesis_node)
    tool(:gate_check, GenesisNodes, :gate_check)
    # Genesis artifacts
    tool(:create_adr, GenesisArtifacts, :create_adr)
    tool(:update_adr, GenesisArtifacts, :update_adr)
    tool(:list_adrs, GenesisArtifacts, :list_adrs)
    tool(:create_feature, GenesisArtifacts, :create_feature)
    tool(:list_features, GenesisArtifacts, :list_features)
    tool(:create_use_case, GenesisArtifacts, :create_use_case)
    tool(:list_use_cases, GenesisArtifacts, :list_use_cases)
    # Genesis gates
    tool(:create_checkpoint, GenesisGates, :create_checkpoint)
    tool(:create_conversation, GenesisGates, :create_conversation)
    tool(:list_conversations, GenesisGates, :list_conversations)
    # Genesis roadmap (Mode C)
    tool(:create_phase, GenesisRoadmap, :create_phase)
    tool(:create_section, GenesisRoadmap, :create_section)
    tool(:create_task, GenesisRoadmap, :create_task)
    tool(:create_subtask, GenesisRoadmap, :create_subtask)
    tool(:list_phases, GenesisRoadmap, :list_phases)
    # DAG execution
    tool(:next_jobs, ProjectExecution, :next_jobs)
    tool(:claim_job, ProjectExecution, :claim_job)
    tool(:complete_job, ProjectExecution, :complete_job)
    tool(:fail_job, ProjectExecution, :fail_job)
    tool(:get_run_status, ProjectExecution, :get_run_status)
    tool(:load_jsonl, ProjectExecution, :load_jsonl)
    tool(:export_jsonl, ProjectExecution, :export_jsonl)
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
    tool(:list_projects, ProjectExecution, :list_projects)
    tool(:create_project, ProjectExecution, :create_project)
    tool(:check_operator_inbox, ProjectExecution, :check_operator_inbox)
    tool(:mes_status, ProjectExecution, :mes_status)
    tool(:cleanup_mes, ProjectExecution, :cleanup_mes)
  end
end
