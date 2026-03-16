defmodule Ichor.AgentTools do
  @moduledoc """
  Ash Domain exposing agent communication tools via MCP.
  Agents connect to Ichor's MCP server to check inbox,
  send messages, and manage tasks.
  """
  use Ash.Domain, extensions: [AshAi]

  alias Ichor.AgentTools.{
    Agents,
    Archival,
    GenesisArtifacts,
    GenesisGates,
    GenesisNodes,
    Inbox,
    Memory,
    Recall,
    Spawn,
    Tasks
  }

  resources do
    resource(Inbox)
    resource(Tasks)
    resource(Memory)
    resource(Recall)
    resource(Archival)
    resource(Agents)
    resource(Spawn)
    resource(GenesisNodes)
    resource(GenesisArtifacts)
    resource(GenesisGates)
  end

  tools do
    # Inbox
    tool(:check_inbox, Inbox, :check_inbox)
    tool(:acknowledge_message, Inbox, :acknowledge_message)
    tool(:send_message, Inbox, :send_message)
    # Tasks
    tool(:get_tasks, Tasks, :get_tasks)
    tool(:update_task_status, Tasks, :update_task_status)
    # Core memory
    tool(:read_memory, Memory, :read_memory)
    tool(:memory_replace, Memory, :memory_replace)
    tool(:memory_insert, Memory, :memory_insert)
    tool(:memory_rethink, Memory, :memory_rethink)
    # Recall
    tool(:conversation_search, Recall, :conversation_search)
    tool(:conversation_search_date, Recall, :conversation_search_date)
    # Archival
    tool(:archival_memory_insert, Archival, :archival_memory_insert)
    tool(:archival_memory_search, Archival, :archival_memory_search)
    # Agent management
    tool(:create_agent, Agents, :create_agent)
    tool(:list_agents, Agents, :list_agents)
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
  end
end
