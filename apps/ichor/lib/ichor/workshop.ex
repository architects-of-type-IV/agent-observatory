defmodule Ichor.Workshop do
  @moduledoc """
  Workshop domain -- design, save, and launch team blueprints.
  The canonical entry point for all workshop operations.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Ichor.Workshop.AgentType)
    resource(Ichor.Workshop.TeamBlueprint)
    resource(Ichor.Workshop.AgentBlueprint)
    resource(Ichor.Workshop.SpawnLink)
    resource(Ichor.Workshop.CommRule)
  end

  @spec blueprint_by_name(String.t()) ::
          {:ok, Ichor.Workshop.TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_name(name), do: Ichor.Workshop.TeamBlueprint.by_name(name)

  @spec agent_type(String.t()) :: {:ok, Ichor.Workshop.AgentType.t()} | {:error, term()}
  def agent_type(id), do: Ichor.Workshop.AgentType.by_id(id)

  @spec create_agent_type(map()) :: {:ok, Ichor.Workshop.AgentType.t()} | {:error, term()}
  def create_agent_type(attrs), do: Ichor.Workshop.AgentType.create(attrs)

  @spec update_agent_type(Ichor.Workshop.AgentType.t(), map()) ::
          {:ok, Ichor.Workshop.AgentType.t()} | {:error, term()}
  def update_agent_type(agent_type, attrs), do: Ichor.Workshop.AgentType.update(agent_type, attrs)

  @spec destroy_agent_type(Ichor.Workshop.AgentType.t()) :: :ok | {:error, term()}
  def destroy_agent_type(agent_type), do: Ichor.Workshop.AgentType.destroy(agent_type)
end
