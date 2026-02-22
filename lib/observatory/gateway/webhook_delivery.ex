defmodule Observatory.Gateway.WebhookDelivery do
  @moduledoc """
  Ecto schema for tracking webhook delivery attempts, retries, and dead-letter state.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "webhook_deliveries" do
    field :target_url, :string
    field :payload, :string
    field :signature, :string
    field :status, :string, default: "pending"
    field :attempt_count, :integer, default: 0
    field :next_retry_at, :utc_datetime
    field :agent_id, :string
    field :webhook_id, :string
    field :inserted_at, :utc_datetime
  end

  @required_fields ~w(target_url payload agent_id)a
  @optional_fields ~w(signature status attempt_count next_retry_at webhook_id inserted_at)a

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ~w(pending delivered failed dead))
  end
end
