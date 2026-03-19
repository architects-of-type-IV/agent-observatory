defmodule Ichor.Control.Persistence do
  @moduledoc """
  Domain-facing persistence helpers for workshop blueprints and agent types.
  """

  alias Ichor.Control
  alias Ichor.Control.BlueprintState

  @doc "Persist workshop state as a blueprint, creating or updating by id."
  @spec save_blueprint(String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def save_blueprint(blueprint_id, state) do
    params = BlueprintState.to_persistence_params(state)

    case blueprint_id do
      nil ->
        Control.create_blueprint(params)

      id ->
        case Control.blueprint_by_id(id) do
          {:ok, blueprint} -> Control.update_blueprint(blueprint, params)
          {:error, _} -> save_blueprint(nil, state)
        end
    end
  end

  @doc "Load a persisted blueprint by id and apply it to the current state."
  @spec load_blueprint(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_blueprint(state, id) do
    with {:ok, blueprint} <- Control.blueprint_by_id(id) do
      {:ok, BlueprintState.apply_blueprint(state, blueprint)}
    end
  end

  @doc "Delete a persisted blueprint by id."
  @spec delete_blueprint(String.t()) :: :ok | {:error, term()}
  def delete_blueprint(id) do
    with {:ok, blueprint} <- Control.blueprint_by_id(id) do
      Control.destroy_blueprint(blueprint)
    end
  end
end
