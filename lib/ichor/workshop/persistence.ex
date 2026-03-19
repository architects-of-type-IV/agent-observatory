defmodule Ichor.Workshop.Persistence do
  @moduledoc """
  Domain-facing persistence helpers for workshop blueprints and agent types.
  """

  alias Ichor.Workshop.AgentType
  alias Ichor.Workshop.BlueprintState
  alias Ichor.Workshop.TeamBlueprint

  @spec list_blueprints() :: [map()]
  def list_blueprints do
    TeamBlueprint.read!(load: [:agent_blueprints, :spawn_links, :comm_rules])
  end

  @spec list_agent_types() :: [map()]
  def list_agent_types, do: AgentType.sorted!()

  @spec save_blueprint(String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def save_blueprint(blueprint_id, state) do
    params = BlueprintState.to_persistence_params(state)

    case blueprint_id do
      nil ->
        TeamBlueprint.create(params)

      id ->
        case TeamBlueprint.by_id(id) do
          {:ok, blueprint} -> TeamBlueprint.update(blueprint, params)
          {:error, _} -> save_blueprint(nil, state)
        end
    end
  end

  @spec load_blueprint(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_blueprint(state, id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id) do
      {:ok, BlueprintState.apply_blueprint(state, blueprint)}
    end
  end

  @spec delete_blueprint(String.t()) :: :ok | {:error, term()}
  def delete_blueprint(id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id) do
      TeamBlueprint.destroy(blueprint)
    end
  end
end
