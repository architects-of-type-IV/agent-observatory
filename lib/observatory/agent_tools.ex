defmodule Observatory.AgentTools do
  @moduledoc """
  Ash Domain exposing agent communication tools via MCP.
  Agents connect to Observatory's MCP server to check inbox,
  send messages, and manage tasks.
  """
  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Observatory.AgentTools.Inbox)
  end

  tools do
    tool(:check_inbox, Observatory.AgentTools.Inbox, :check_inbox)
    tool(:acknowledge_message, Observatory.AgentTools.Inbox, :acknowledge_message)
    tool(:send_message, Observatory.AgentTools.Inbox, :send_message)
    tool(:get_tasks, Observatory.AgentTools.Inbox, :get_tasks)
    tool(:update_task_status, Observatory.AgentTools.Inbox, :update_task_status)
  end
end
