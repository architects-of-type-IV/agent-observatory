defmodule Ichor.Fleet.Runtime do
  @moduledoc """
  Explicit boundary for fleet runtime operations.

  This is the live control plane over agent processes, team supervisors,
  lifecycle orchestration, and host discovery.
  """

  alias Ichor.Fleet.{AgentProcess, FleetSupervisor, HostRegistry, Lifecycle, TeamSupervisor}

  defdelegate list_agents(), to: AgentProcess, as: :list_all
  defdelegate lookup_agent(agent_id), to: AgentProcess, as: :lookup
  defdelegate agent_alive?(agent_id), to: AgentProcess, as: :alive?
  defdelegate send_message(agent_id, message), to: AgentProcess
  defdelegate pause_agent(agent_id), to: AgentProcess, as: :pause
  defdelegate resume_agent(agent_id), to: AgentProcess, as: :resume

  defdelegate create_team(opts), to: FleetSupervisor
  defdelegate disband_team(team_name), to: FleetSupervisor
  defdelegate spawn_standalone_agent(opts), to: FleetSupervisor, as: :spawn_agent
  defdelegate terminate_standalone_agent(agent_id), to: FleetSupervisor, as: :terminate_agent

  defdelegate spawn_team_member(team_name, opts), to: TeamSupervisor, as: :spawn_member

  defdelegate terminate_team_member(team_name, agent_id),
    to: TeamSupervisor,
    as: :terminate_member

  defdelegate list_teams(), to: TeamSupervisor, as: :list_all
  defdelegate team_exists?(team_name), to: TeamSupervisor, as: :exists?
  defdelegate team_member_ids(team_name), to: TeamSupervisor, as: :member_ids

  defdelegate spawn_agent(opts), to: Lifecycle
  defdelegate stop_agent(agent_id), to: Lifecycle
  defdelegate kill_session(session), to: Lifecycle

  defdelegate list_hosts(), to: HostRegistry
  defdelegate get_host(node_name), to: HostRegistry
  defdelegate register_host(node_name, metadata), to: HostRegistry
  defdelegate remove_host(node_name), to: HostRegistry
  defdelegate host_available?(node_name), to: HostRegistry, as: :available?
end
