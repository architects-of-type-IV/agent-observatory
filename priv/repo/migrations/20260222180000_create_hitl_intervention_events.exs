defmodule Observatory.Repo.Migrations.CreateHitlInterventionEvents do
  use Ecto.Migration

  def change do
    create table(:hitl_intervention_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :agent_id, :string
      add :operator_id, :string, null: false
      add :action, :string, null: false
      add :details, :text
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:hitl_intervention_events, [:session_id])
    create index(:hitl_intervention_events, [:operator_id])
  end
end
