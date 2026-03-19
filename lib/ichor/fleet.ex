defmodule Ichor.Fleet do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Fleet.Agent
  alias Ichor.Fleet.Team

  resources do
    resource(Ichor.Fleet.Agent)
    resource(Ichor.Fleet.Team)
  end

  @spec list_agents() :: list(Agent.t())
  def list_agents, do: Agent.all!()

  @spec list_active_agents() :: list(Agent.t())
  def list_active_agents, do: Agent.active!()

  @spec list_alive_teams() :: list(Team.t())
  def list_alive_teams, do: Team.alive!()

  @spec list_teams() :: list(Team.t())
  def list_teams, do: Team.all!()

  @spec get_unread(String.t()) :: {:ok, list(map())}
  def get_unread(agent_id), do: Agent.get_unread(agent_id)

  @spec mark_read(String.t(), String.t()) :: {:ok, map()}
  def mark_read(agent_id, message_id), do: Agent.mark_read(agent_id, message_id)
end
