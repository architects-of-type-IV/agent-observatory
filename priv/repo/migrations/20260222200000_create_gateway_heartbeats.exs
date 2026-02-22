defmodule Observatory.Repo.Migrations.CreateGatewayHeartbeats do
  use Ecto.Migration

  def change do
    create table(:gateway_heartbeats, primary_key: false) do
      add :agent_id, :string, primary_key: true
      add :cluster_id, :string
      add :last_seen_at, :utc_datetime
    end
  end
end
