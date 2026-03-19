defmodule Ichor.Mesh.DecisionLog.Meta do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          trace_id: String.t() | nil,
          timestamp: DateTime.t() | nil,
          parent_step_id: String.t() | nil,
          cluster_id: String.t() | nil,
          source_app: String.t() | nil,
          tool_use_id: String.t() | nil,
          event_id: String.t() | nil
        }

  @primary_key false
  embedded_schema do
    field :trace_id, :string
    field :timestamp, :utc_datetime
    field :parent_step_id, :string
    field :cluster_id, :string
    field :source_app, :string
    field :tool_use_id, :string
    field :event_id, :string
  end

  @required_fields ~w(trace_id timestamp)a
  @optional_fields ~w(parent_step_id cluster_id source_app tool_use_id event_id)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> update_change(:parent_step_id, fn val -> if val == "", do: nil, else: val end)
    |> validate_required(@required_fields)
  end
end
