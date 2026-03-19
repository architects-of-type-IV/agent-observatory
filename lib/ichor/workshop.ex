defmodule Ichor.Workshop do
  @moduledoc """
  Workshop domain -- design, save, and launch team blueprints.
  The canonical entry point for all workshop operations.
  """

  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Workshop.AgentType
  alias Ichor.Workshop.TeamBlueprint

  resources do
    resource(Ichor.Workshop.AgentType)
    resource(Ichor.Workshop.TeamBlueprint)
    resource(Ichor.Workshop.AgentBlueprint)
    resource(Ichor.Workshop.SpawnLink)
    resource(Ichor.Workshop.CommRule)
  end

  @spec blueprint_by_name(String.t()) ::
          {:ok, TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_name(name), do: TeamBlueprint.by_name(name)

  @spec agent_type(String.t()) :: {:ok, AgentType.t()} | {:error, term()}
  def agent_type(id), do: AgentType.by_id(id)

  @spec create_agent_type(map()) :: {:ok, AgentType.t()} | {:error, term()}
  def create_agent_type(attrs), do: AgentType.create(attrs)

  @spec update_agent_type(AgentType.t(), map()) ::
          {:ok, AgentType.t()} | {:error, term()}
  def update_agent_type(agent_type, attrs), do: AgentType.update(agent_type, attrs)

  @spec destroy_agent_type(AgentType.t()) :: :ok | {:error, term()}
  def destroy_agent_type(agent_type), do: AgentType.destroy(agent_type)
end
