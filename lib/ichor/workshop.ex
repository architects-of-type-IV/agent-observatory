defmodule Ichor.Workshop do
  @moduledoc """
  Ash Domain: Workshop team and agent authoring.

  Owns reusable agent types, saved team definitions, persisted team members,
  and the runtime-facing agent/team resource surfaces used by the frontend.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Workshop.Agent)
    resource(Ichor.Workshop.ActiveTeam)
    resource(Ichor.Workshop.Team)
    resource(Ichor.Workshop.TeamMember)
    resource(Ichor.Workshop.AgentType)
    resource(Ichor.Workshop.AgentMemory)
  end

  tools do
    tool(:spawn_agent, Ichor.Workshop.Agent, :spawn_agent)
    tool(:stop_agent, Ichor.Workshop.Agent, :stop_agent)
    tool(:list_archon_agents, Ichor.Workshop.Agent, :list_live_agents)
    tool(:agent_status, Ichor.Workshop.Agent, :agent_status)
    tool(:spawn_archon_agent, Ichor.Workshop.Agent, :spawn_archon_agent)
    tool(:pause_agent, Ichor.Workshop.Agent, :pause_agent)
    tool(:resume_agent, Ichor.Workshop.Agent, :resume_agent)
    tool(:list_teams, Ichor.Workshop.ActiveTeam, :list_teams)
    tool(:read_memory, Ichor.Workshop.AgentMemory, :read_memory)
    tool(:memory_replace, Ichor.Workshop.AgentMemory, :memory_replace)
    tool(:memory_insert, Ichor.Workshop.AgentMemory, :memory_insert)
    tool(:memory_rethink, Ichor.Workshop.AgentMemory, :memory_rethink)
    tool(:conversation_search, Ichor.Workshop.AgentMemory, :conversation_search)
    tool(:conversation_search_date, Ichor.Workshop.AgentMemory, :conversation_search_date)
    tool(:archival_memory_insert, Ichor.Workshop.AgentMemory, :archival_memory_insert)
    tool(:archival_memory_search, Ichor.Workshop.AgentMemory, :archival_memory_search)
    tool(:create_agent, Ichor.Workshop.AgentMemory, :create_agent)
    tool(:list_agents, Ichor.Workshop.AgentMemory, :list_registered_agents)
  end
end
