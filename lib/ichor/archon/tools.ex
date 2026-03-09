defmodule Ichor.Archon.Tools do
  @moduledoc """
  Tool domain for Archon. Exposes fleet, messaging, and system
  query tools via AshAi for LLM tool-use integration.
  """
  use Ash.Domain, extensions: [AshAi]
  alias Ichor.Archon.Tools.Agents
  alias Ichor.Archon.Tools.Teams
  alias Ichor.Archon.Tools.Messages
  alias Ichor.Archon.Tools.System
  alias Ichor.Archon.Tools.Memory

  resources do
    resource(Agents)
    resource(Teams)
    resource(Messages)
    resource(System)
    resource(Memory)
  end

  tools do
    # Fleet
    tool(:list_agents, Agents, :list_agents)
    tool(:agent_status, Agents, :agent_status)
    tool(:list_teams, Teams, :list_teams)
    # Messaging
    tool(:recent_messages, Messages, :recent_messages)
    tool(:send_message, Messages, :send_message)
    # System
    tool(:system_health, System, :system_health)
    tool(:tmux_sessions, System, :tmux_sessions)
    # Memory
    tool(:search_memory, Memory, :search_memory)
    tool(:remember, Memory, :remember)
    tool(:query_memory, Memory, :query_memory)
  end
end
