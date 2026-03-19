defmodule Ichor.Mesh.DecisionLog.StateDelta do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          added_to_memory: [String.t()] | nil,
          tokens_consumed: integer() | nil,
          cumulative_session_cost: float() | nil
        }

  @primary_key false
  embedded_schema do
    field :added_to_memory, {:array, :string}
    field :tokens_consumed, :integer
    field :cumulative_session_cost, :float
  end

  @all_fields ~w(added_to_memory tokens_consumed cumulative_session_cost)a

  def changeset(struct, params) do
    cast(struct, params, @all_fields)
  end
end
