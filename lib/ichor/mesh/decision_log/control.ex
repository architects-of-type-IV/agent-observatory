defmodule Ichor.Mesh.DecisionLog.Control do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          hitl_required: boolean(),
          interrupt_signal: String.t() | nil,
          is_terminal: boolean()
        }

  @primary_key false
  embedded_schema do
    field :hitl_required, :boolean, default: false
    field :interrupt_signal, :string
    field :is_terminal, :boolean, default: false
  end

  @all_fields ~w(hitl_required interrupt_signal is_terminal)a

  def changeset(struct, params) do
    cast(struct, params, @all_fields)
  end
end
