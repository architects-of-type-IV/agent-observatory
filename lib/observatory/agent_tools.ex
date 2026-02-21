defmodule Observatory.AgentTools do
  @moduledoc """
  Ash Domain exposing agent communication tools via MCP.
  Agents connect to Observatory's MCP server to check inbox,
  send messages, and manage tasks.
  """
  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Observatory.AgentTools.Inbox)
    resource(Observatory.AgentTools.Memory)
  end

  tools do
    # Inbox
    tool(:check_inbox, Observatory.AgentTools.Inbox, :check_inbox)
    tool(:acknowledge_message, Observatory.AgentTools.Inbox, :acknowledge_message)
    tool(:send_message, Observatory.AgentTools.Inbox, :send_message)
    tool(:get_tasks, Observatory.AgentTools.Inbox, :get_tasks)
    tool(:update_task_status, Observatory.AgentTools.Inbox, :update_task_status)
    # Memory (Letta-compatible)
    tool(:read_memory, Observatory.AgentTools.Memory, :read_memory)
    tool(:memory_replace, Observatory.AgentTools.Memory, :memory_replace)
    tool(:memory_insert, Observatory.AgentTools.Memory, :memory_insert)
    tool(:memory_rethink, Observatory.AgentTools.Memory, :memory_rethink)
    tool(:conversation_search, Observatory.AgentTools.Memory, :conversation_search)
    tool(:conversation_search_date, Observatory.AgentTools.Memory, :conversation_search_date)
    tool(:archival_memory_insert, Observatory.AgentTools.Memory, :archival_memory_insert)
    tool(:archival_memory_search, Observatory.AgentTools.Memory, :archival_memory_search)
    tool(:create_agent, Observatory.AgentTools.Memory, :create_agent)
    tool(:list_agents, Observatory.AgentTools.Memory, :list_agents)
  end
end
