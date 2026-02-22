defmodule Observatory.Repo.Migrations.CreateCronJobs do
  use Ecto.Migration

  def change do
    create table(:cron_jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, :string, null: false
      add :payload, :text, null: false
      add :next_fire_at, :utc_datetime, null: false
      add :is_one_time, :boolean, default: true, null: false
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:cron_jobs, [:agent_id])
    create index(:cron_jobs, [:next_fire_at])
  end
end
