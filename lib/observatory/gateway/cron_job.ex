defmodule Observatory.Gateway.CronJob do
  @moduledoc """
  Ecto schema for the `cron_jobs` SQLite table.

  Stores scheduled one-time or recurring jobs that fire at `next_fire_at`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "cron_jobs" do
    field :agent_id, :string
    field :payload, :string
    field :next_fire_at, :utc_datetime
    field :is_one_time, :boolean, default: true
    field :inserted_at, :utc_datetime
  end

  @required_fields ~w(agent_id payload next_fire_at)a
  @optional_fields ~w(is_one_time inserted_at)a

  def changeset(struct, params) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
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
