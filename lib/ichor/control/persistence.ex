defmodule Ichor.Control.Persistence do
  @moduledoc """
  Domain-facing persistence helpers for workshop blueprints and agent types.
  """

  alias Ichor.Control.BlueprintState
  alias Ichor.Control.TeamBlueprint

  @doc "Persist workshop state as a blueprint, creating or updating by id."
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

  @doc "Load a persisted blueprint by id and apply it to the current state."
  @spec load_blueprint(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_blueprint(state, id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id) do
      {:ok, BlueprintState.apply_blueprint(state, blueprint)}
    end
  end

  @doc "Delete a persisted blueprint by id."
  @spec delete_blueprint(String.t()) :: :ok | {:error, term()}
  def delete_blueprint(id) do
    with {:ok, blueprint} <- TeamBlueprint.by_id(id) do
      TeamBlueprint.destroy(blueprint)
    end
  end
end
