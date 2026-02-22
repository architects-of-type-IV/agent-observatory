defmodule Observatory.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :target_url, :string, null: false
      add :payload, :text, null: false
      add :signature, :string
      add :status, :string, null: false, default: "pending"
      add :attempt_count, :integer, null: false, default: 0
      add :next_retry_at, :utc_datetime
      add :agent_id, :string, null: false
      add :webhook_id, :string
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:webhook_deliveries, [:status])
    create index(:webhook_deliveries, [:next_retry_at])
    create index(:webhook_deliveries, [:agent_id])
  end
end
