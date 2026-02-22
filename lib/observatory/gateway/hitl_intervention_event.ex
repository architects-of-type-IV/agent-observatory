defmodule Observatory.Gateway.HITLInterventionEvent do
  @moduledoc """
  Ecto schema for the `hitl_intervention_events` table.

  Records an audit trail entry each time an operator issues a HITL command
  (pause, unpause, rewrite, inject).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "hitl_intervention_events" do
    field :session_id, :string
    field :agent_id, :string
    field :operator_id, :string
    field :action, :string
    field :details, :string
    field :inserted_at, :utc_datetime
  end

  @required_fields ~w(session_id operator_id action)a
  @optional_fields ~w(agent_id details inserted_at)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:action, ~w(pause unpause rewrite inject))
    |> maybe_set_inserted_at()
  end

  defp maybe_set_inserted_at(changeset) do
    if get_field(changeset, :inserted_at) do
      changeset
    else
      put_change(changeset, :inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
    end
  end
end
