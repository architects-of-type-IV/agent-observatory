defmodule Observatory.Gateway.HeartbeatRecord do
  @moduledoc """
  Embedded schema representing a gateway heartbeat record.
  Maps to the `gateway_heartbeats` table for persistence.
  """

  use Ecto.Schema

  @primary_key {:agent_id, :string, autogenerate: false}
  schema "gateway_heartbeats" do
    field :cluster_id, :string
    field :last_seen_at, :utc_datetime
  end
end
