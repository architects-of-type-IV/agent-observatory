defmodule Ichor.Tools do
  @moduledoc """
  Ash Domain: MCP tool surfaces for agents and the Archon.

  Capability-based organization. Exposure scoped per MCP endpoint
  (/mcp/agent, /mcp/archon) via router tool lists.
  """
  use Ash.Domain, extensions: [AshAi], validate_config_inclusion?: true

  alias Ichor.Tools.Agent.Agents
  alias Ichor.Tools.Agent.Archival
  alias Ichor.Tools.Agent.DagExecution
  alias Ichor.Tools.Agent.GenesisArtifacts
  alias Ichor.Tools.Agent.GenesisGates
  alias Ichor.Tools.Agent.GenesisNodes
  alias Ichor.Tools.Agent.GenesisRoadmap
  alias Ichor.Tools.Agent.Inbox
  alias Ichor.Tools.Agent.Memory, as: AgentMemory
  alias Ichor.Tools.Agent.Recall
  alias Ichor.Tools.Agent.Spawn
  alias Ichor.Tools.Agent.Tasks

  alias Ichor.Tools.Archon.Agents, as: ArchonAgents
  alias Ichor.Tools.Archon.Control
  alias Ichor.Tools.Archon.Events
  alias Ichor.Tools.Archon.Manager
  alias Ichor.Tools.Archon.Memory, as: ArchonMemory
  alias Ichor.Tools.Archon.Mes
  alias Ichor.Tools.Archon.Messages
  alias Ichor.Tools.Archon.System, as: ArchonSystem
  alias Ichor.Tools.Archon.Teams

  resources do
    # Agent tools (12)
    resource(Inbox)
    resource(Tasks)
    resource(AgentMemory)
    resource(Recall)
    resource(Archival)
    resource(Agents)
    resource(Spawn)
    resource(GenesisNodes)
    resource(GenesisArtifacts)
    resource(GenesisGates)
    resource(GenesisRoadmap)
    resource(DagExecution)
    # Archon tools (9)
    resource(ArchonAgents)
    resource(Teams)
    resource(Messages)
    resource(ArchonSystem)
    resource(Manager)
    resource(ArchonMemory)
    resource(Control)
    resource(Events)
    resource(Mes)
  end

  tools do
    # Inbox
    tool(:check_inbox, Inbox, :check_inbox)
    tool(:acknowledge_message, Inbox, :acknowledge_message)
    tool(:send_message, Inbox, :agent_send_message)
    # Tasks
    tool(:get_tasks, Tasks, :get_tasks)
    tool(:update_task_status, Tasks, :update_task_status)
    # Core memory
    tool(:read_memory, AgentMemory, :read_memory)
    tool(:memory_replace, AgentMemory, :memory_replace)
    tool(:memory_insert, AgentMemory, :memory_insert)
    tool(:memory_rethink, AgentMemory, :memory_rethink)
    # Recall
    tool(:conversation_search, Recall, :conversation_search)
    tool(:conversation_search_date, Recall, :conversation_search_date)
    # Archival
    tool(:archival_memory_insert, Archival, :archival_memory_insert)
    tool(:archival_memory_search, Archival, :archival_memory_search)
    # Agent management
    tool(:create_agent, Agents, :create_agent)
    tool(:list_agents, Agents, :list_registered_agents)
    # Fleet spawning
    tool(:spawn_agent, Spawn, :spawn_agent)
    tool(:stop_agent, Spawn, :stop_agent)
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
    tool(:next_jobs, DagExecution, :next_jobs)
    tool(:claim_job, DagExecution, :claim_job)
    tool(:complete_job, DagExecution, :complete_job)
    tool(:fail_job, DagExecution, :fail_job)
    tool(:get_run_status, DagExecution, :get_run_status)
    tool(:load_jsonl, DagExecution, :load_jsonl)
    tool(:export_jsonl, DagExecution, :export_jsonl)
    # Fleet observation (Archon)
    tool(:list_archon_agents, ArchonAgents, :list_live_agents)
    tool(:agent_status, ArchonAgents, :agent_status)
    tool(:list_teams, Teams, :list_teams)
    # Fleet control (Archon)
    tool(:spawn_archon_agent, Control, :spawn_agent)
    tool(:stop_archon_agent, Control, :stop_agent)
    tool(:pause_agent, Control, :pause_agent)
    tool(:resume_agent, Control, :resume_agent)
    tool(:sweep, Control, :sweep)
    # Messaging (Archon)
    tool(:recent_messages, Messages, :recent_messages)
    tool(:archon_send_message, Messages, :operator_send_message)
    # System (Archon)
    tool(:system_health, ArchonSystem, :system_health)
    tool(:tmux_sessions, ArchonSystem, :tmux_sessions)
    tool(:manager_snapshot, Manager, :manager_snapshot)
    tool(:attention_queue, Manager, :attention_queue)
    # Events & tasks (Archon)
    tool(:agent_events, Events, :agent_events)
    tool(:fleet_tasks, Events, :fleet_tasks)
    # Memory (Archon)
    tool(:search_memory, ArchonMemory, :search_memory)
    tool(:remember, ArchonMemory, :remember)
    tool(:query_memory, ArchonMemory, :query_memory)
    # MES floor management (Archon)
    tool(:list_projects, Mes, :list_projects)
    tool(:create_project, Mes, :create_project)
    tool(:check_operator_inbox, Mes, :check_operator_inbox)
    tool(:mes_status, Mes, :mes_status)
    tool(:cleanup_mes, Mes, :cleanup_mes)
  end
end
