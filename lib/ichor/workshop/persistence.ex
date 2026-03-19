defmodule Ichor.Workshop.Persistence do
  @moduledoc """
  Domain-facing persistence helpers for workshop blueprints and agent types.
  """

  alias Ichor.Workshop
  alias Ichor.Workshop.BlueprintState

  @spec save_blueprint(String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def save_blueprint(blueprint_id, state) do
    params = BlueprintState.to_persistence_params(state)

    case blueprint_id do
      nil ->
        Workshop.create_blueprint(params)

      id ->
        case Workshop.blueprint_by_id(id) do
          {:ok, blueprint} -> Workshop.update_blueprint(blueprint, params)
          {:error, _} -> save_blueprint(nil, state)
        end
    end
  end

  @spec load_blueprint(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def load_blueprint(state, id) do
    with {:ok, blueprint} <- Workshop.blueprint_by_id(id) do
      {:ok, BlueprintState.apply_blueprint(state, blueprint)}
    end
  end

  @spec delete_blueprint(String.t()) :: :ok | {:error, term()}
  def delete_blueprint(id) do
    with {:ok, blueprint} <- Workshop.blueprint_by_id(id) do
      Workshop.destroy_blueprint(blueprint)
    end
  end
end
