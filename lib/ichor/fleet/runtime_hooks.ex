defmodule Ichor.Fleet.RuntimeHooks do
  @moduledoc """
  Product-side runtime adapter used by the extracted Fleet view app.
  """

  alias Ichor.EventBuffer
  alias Ichor.Fleet.AgentProcess
  alias Ichor.Fleet.Analysis.AgentHealth
  alias Ichor.Fleet.Lifecycle.AgentLaunch
  alias Ichor.Fleet.Runtime

  def list_agents, do: AgentProcess.list_all()
  def pause_agent(agent_id), do: AgentProcess.pause(agent_id)
  def resume_agent(agent_id), do: AgentProcess.resume(agent_id)
  def lookup_agent(agent_id), do: AgentProcess.lookup(agent_id)
  def agent_alive?(agent_id), do: AgentProcess.alive?(agent_id)
  def agent_unread(agent_id), do: AgentProcess.get_unread(agent_id)

  def send_agent_message(agent_id, payload) do
    AgentProcess.send_message(agent_id, payload)
  end

  def launch_agent(opts), do: AgentLaunch.spawn(opts)
  def spawn_standalone_agent(opts), do: Runtime.spawn_standalone_agent(opts)
  def terminate_standalone_agent(agent_id), do: Runtime.terminate_standalone_agent(agent_id)
  def team_exists?(team_name), do: Runtime.team_exists?(team_name)
  def create_team(opts), do: Runtime.create_team(opts)
  def disband_team(team_name), do: Runtime.disband_team(team_name)
  def spawn_team_member(team_name, opts), do: Runtime.spawn_team_member(team_name, opts)

  def terminate_team_member(team_name, agent_id),
    do: Runtime.terminate_team_member(team_name, agent_id)

  def list_teams, do: Runtime.list_teams()
  def team_member_ids(team_name), do: Runtime.team_member_ids(team_name)
  def list_events, do: EventBuffer.list_events()
  def compute_agent_health(events, now), do: AgentHealth.compute_agent_health(events, now)
end
