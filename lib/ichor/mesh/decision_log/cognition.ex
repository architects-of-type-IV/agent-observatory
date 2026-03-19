defmodule Ichor.Mesh.DecisionLog.Cognition do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          intent: String.t() | nil,
          reasoning_chain: [String.t()] | nil,
          confidence_score: float() | nil,
          strategy_used: String.t() | nil,
          entropy_score: float() | nil,
          hook_event_type: String.t() | nil,
          summary: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :intent, :string
    field :reasoning_chain, {:array, :string}
    field :confidence_score, :float
    field :strategy_used, :string
    field :entropy_score, :float
    field :hook_event_type, :string
    field :summary, :string
  end

  @required_fields ~w(intent)a
  @optional_fields ~w(reasoning_chain confidence_score strategy_used entropy_score hook_event_type summary)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
