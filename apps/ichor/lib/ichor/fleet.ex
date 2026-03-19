defmodule Ichor.Fleet do
  use Ash.Domain, validate_config_inclusion?: false
  @moduledoc false

  resources do
    resource(Ichor.Fleet.Agent)
    resource(Ichor.Fleet.Team)
  end

  @spec list_agents() :: list(Ichor.Fleet.Agent.t())
  def list_agents, do: Ichor.Fleet.Agent.all!()

  @spec list_active_agents() :: list(Ichor.Fleet.Agent.t())
  def list_active_agents, do: Ichor.Fleet.Agent.active!()

  @spec list_alive_teams() :: list(Ichor.Fleet.Team.t())
  def list_alive_teams, do: Ichor.Fleet.Team.alive!()

  @spec list_teams() :: list(Ichor.Fleet.Team.t())
  def list_teams, do: Ichor.Fleet.Team.all!()

  @spec get_unread(String.t()) :: {:ok, list(map())}
  def get_unread(agent_id), do: Ichor.Fleet.Agent.get_unread(agent_id)

  @spec mark_read(String.t(), String.t()) :: {:ok, map()}
  def mark_read(agent_id, message_id), do: Ichor.Fleet.Agent.mark_read(agent_id, message_id)
end
