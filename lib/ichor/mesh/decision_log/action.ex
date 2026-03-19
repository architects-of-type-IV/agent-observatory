defmodule Ichor.Mesh.DecisionLog.Action do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          status: :success | :failure | :pending | :skipped | nil,
          tool_call: String.t() | nil,
          tool_input: String.t() | nil,
          tool_output_summary: String.t() | nil,
          duration_ms: integer() | nil,
          permission_mode: String.t() | nil,
          cwd: String.t() | nil,
          payload: map() | nil
        }

  @primary_key false
  embedded_schema do
    field :status, Ecto.Enum, values: [:success, :failure, :pending, :skipped]
    field :tool_call, :string
    field :tool_input, :string
    field :tool_output_summary, :string
    field :duration_ms, :integer
    field :permission_mode, :string
    field :cwd, :string
    field :payload, :map
  end

  @required_fields ~w(status)a
  @optional_fields ~w(tool_call tool_input tool_output_summary duration_ms permission_mode cwd payload)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
