defmodule Observatory.Archon.Tools do
  @moduledoc """
  Tool domain for Archon. Exposes fleet, messaging, and system
  query tools via AshAi for LLM tool-use integration.
  """
  use Ash.Domain, extensions: [AshAi]
  alias Observatory.Archon.Tools.Agents
  alias Observatory.Archon.Tools.Teams
  alias Observatory.Archon.Tools.Messages
  alias Observatory.Archon.Tools.System

  resources do
    resource(Agents)
    resource(Teams)
    resource(Messages)
    resource(System)
  end

  tools do
    tool(:list_agents, Agents, :list_agents)
    tool(:agent_status, Agents, :agent_status)
    tool(:list_teams, Teams, :list_teams)
    tool(:recent_messages, Messages, :recent_messages)
    tool(:send_message, Messages, :send_message)
    tool(:system_health, System, :system_health)
    tool(:tmux_sessions, System, :tmux_sessions)
  end
end
