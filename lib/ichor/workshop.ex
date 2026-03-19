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

  @doc "Returns all blueprints with agent_blueprints, spawn_links, and comm_rules loaded."
  @spec list_blueprints() :: [TeamBlueprint.t()]
  def list_blueprints do
    TeamBlueprint.read!(load: [:agent_blueprints, :spawn_links, :comm_rules])
  end

  @doc "Returns all agent types sorted by sort_order asc, name asc."
  @spec list_agent_types() :: [AgentType.t()]
  def list_agent_types, do: AgentType.sorted!()

  @doc "Fetches a single blueprint by id with relationships loaded."
  @spec blueprint_by_id(String.t()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_id(id), do: TeamBlueprint.by_id(id)

  @doc "Fetches a single blueprint by name with relationships loaded."
  @spec blueprint_by_name(String.t()) ::
          {:ok, TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_name(name), do: TeamBlueprint.by_name(name)

  @doc "Creates a blueprint from the given attrs map."
  @spec create_blueprint(map()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def create_blueprint(attrs), do: TeamBlueprint.create(attrs)

  @doc "Updates an existing blueprint with the given attrs map."
  @spec update_blueprint(TeamBlueprint.t(), map()) ::
          {:ok, TeamBlueprint.t()} | {:error, term()}
  def update_blueprint(blueprint, attrs), do: TeamBlueprint.update(blueprint, attrs)

  @doc "Destroys a blueprint record."
  @spec destroy_blueprint(TeamBlueprint.t()) :: :ok | {:error, term()}
  def destroy_blueprint(blueprint), do: TeamBlueprint.destroy(blueprint)

  @doc "Returns a single agent type by id."
  @spec agent_type(String.t()) :: {:ok, AgentType.t()} | {:error, term()}
  def agent_type(id), do: AgentType.by_id(id)

  @doc "Creates an agent type from the given attrs map."
  @spec create_agent_type(map()) :: {:ok, AgentType.t()} | {:error, term()}
  def create_agent_type(attrs), do: AgentType.create(attrs)

  @doc "Updates an existing agent type with the given attrs map."
  @spec update_agent_type(AgentType.t(), map()) ::
          {:ok, AgentType.t()} | {:error, term()}
  def update_agent_type(agent_type, attrs), do: AgentType.update(agent_type, attrs)

  @doc "Destroys an agent type record."
  @spec destroy_agent_type(AgentType.t()) :: :ok | {:error, term()}
  def destroy_agent_type(agent_type), do: AgentType.destroy(agent_type)
end
