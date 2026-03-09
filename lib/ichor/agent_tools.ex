defmodule Ichor.AgentTools do
  @moduledoc """
  Ash Domain exposing agent communication tools via MCP.
  Agents connect to Ichor's MCP server to check inbox,
  send messages, and manage tasks.
  """
  use Ash.Domain, extensions: [AshAi]

  alias Ichor.AgentTools.{Inbox, Tasks, Memory, Recall, Archival, Agents, Spawn}

  resources do
    resource(Inbox)
    resource(Tasks)
    resource(Memory)
    resource(Recall)
    resource(Archival)
    resource(Agents)
    resource(Spawn)
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
  end
end
