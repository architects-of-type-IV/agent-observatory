defmodule Ichor.Mesh.DecisionLog.Identity do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          agent_id: String.t() | nil,
          agent_type: String.t() | nil,
          capability_version: String.t() | nil,
          model_name: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :agent_id, :string
    field :agent_type, :string
    field :capability_version, :string
    field :model_name, :string
  end

  @required_fields ~w(agent_id agent_type capability_version)a
  @optional_fields ~w(model_name)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
