defmodule Ichor.Archon.Tools do
  @moduledoc """
  Tool domain for Archon. Exposes fleet, messaging, and system
  query tools via AshAi for LLM tool-use integration.
  """
  use Ash.Domain, extensions: [AshAi]
  alias Ichor.Archon.Tools.Agents
  alias Ichor.Archon.Tools.Control
  alias Ichor.Archon.Tools.Events
  alias Ichor.Archon.Tools.Memory
  alias Ichor.Archon.Tools.Messages
  alias Ichor.Archon.Tools.System
  alias Ichor.Archon.Tools.Teams

  resources do
    resource(Agents)
    resource(Teams)
    resource(Messages)
    resource(System)
    resource(Memory)
    resource(Control)
    resource(Events)
  end

  tools do
    # Fleet observation
    tool(:list_agents, Agents, :list_agents)
    tool(:agent_status, Agents, :agent_status)
    tool(:list_teams, Teams, :list_teams)
    # Fleet control
    tool(:spawn_agent, Control, :spawn_agent)
    tool(:stop_agent, Control, :stop_agent)
    tool(:pause_agent, Control, :pause_agent)
    tool(:resume_agent, Control, :resume_agent)
    tool(:sweep, Control, :sweep)
    # Messaging
    tool(:recent_messages, Messages, :recent_messages)
    tool(:send_message, Messages, :send_message)
    # System
    tool(:system_health, System, :system_health)
    tool(:tmux_sessions, System, :tmux_sessions)
    # Events & tasks
    tool(:agent_events, Events, :agent_events)
    tool(:fleet_tasks, Events, :fleet_tasks)
    # Memory
    tool(:search_memory, Memory, :search_memory)
    tool(:remember, Memory, :remember)
    tool(:query_memory, Memory, :query_memory)
  end
end
