defmodule Ichor.Repo.Migrations.CreateGenesisRoadmapHierarchy do
  use Ecto.Migration

  def up do
    create table(:genesis_phases, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :number, :integer, null: false
      add :title, :text, null: false
      add :goals, {:array, :text}, default: []
      add :status, :text, null: false, default: "pending"
      add :governed_by, {:array, :text}, default: []
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_phases, [:node_id])

    create table(:genesis_sections, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :number, :integer, null: false
      add :title, :text, null: false
      add :goal, :text
      add :phase_id, references(:genesis_phases, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_sections, [:phase_id])

    create table(:genesis_tasks, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :number, :integer, null: false
      add :title, :text, null: false
      add :governed_by, {:array, :text}, default: []
      add :parent_uc, :text
      add :status, :text, null: false, default: "pending"
      add :section_id, references(:genesis_sections, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_tasks, [:section_id])

    create table(:genesis_subtasks, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :number, :integer, null: false
      add :title, :text, null: false
      add :goal, :text
      add :allowed_files, {:array, :text}, default: []
      add :blocked_by, {:array, :text}, default: []
      add :steps, {:array, :text}, default: []
      add :done_when, :text
      add :status, :text, null: false, default: "pending"
      add :owner, :text
      add :task_id, references(:genesis_tasks, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_subtasks, [:task_id])
  end

  def down do
    drop table(:genesis_subtasks)
    drop table(:genesis_tasks)
    drop table(:genesis_sections)
    drop table(:genesis_phases)
  end
end
