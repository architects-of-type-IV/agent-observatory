defmodule Ichor.Workshop.Persistence do
  @moduledoc """
  Domain-facing persistence helpers for workshop blueprints and agent types.
  """

  alias Ichor.Workshop.BlueprintState
  alias Ichor.Workshop.{AgentType, TeamBlueprint}

  @spec list_blueprints() :: [map()]
  def list_blueprints do
    TeamBlueprint.read!()
    |> Ash.load!([:agent_blueprints, :spawn_links, :comm_rules])
  end

  @spec list_agent_types() :: [map()]
  def list_agent_types, do: AgentType.sorted!()

  @spec save_blueprint(String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def save_blueprint(blueprint_id, state) do
    params = BlueprintState.to_persistence_params(state)

    case blueprint_id do
      nil ->
        TeamBlueprint
        |> Ash.Changeset.for_create(:create, params)
        |> Ash.create()

      id ->
        with {:ok, blueprint} <- TeamBlueprint.by_id(id) do
          blueprint
          |> Ash.Changeset.for_update(:update, params)
          |> Ash.update()
        else
          {:error, _} -> save_blueprint(nil, state)
        end
    end
  end

  @spec load_blueprint(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_blueprint(state, id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id),
         {:ok, loaded} <- Ash.load(blueprint, [:agent_blueprints, :spawn_links, :comm_rules]) do
      {:ok, BlueprintState.apply_blueprint(state, loaded)}
    end
  end

  @spec delete_blueprint(String.t()) :: :ok | {:error, term()}
  def delete_blueprint(id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id),
         :ok <- Ash.destroy(blueprint) do
      :ok
    end
  end
end
