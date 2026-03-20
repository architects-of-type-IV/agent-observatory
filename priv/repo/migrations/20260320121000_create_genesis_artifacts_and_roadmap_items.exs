defmodule Ichor.Repo.Migrations.CreateGenesisArtifactsAndRoadmapItems do
  use Ecto.Migration

  def up do
    create table(:genesis_artifacts, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :kind, :text, null: false
      add :title, :text, null: false
      add :content, :text
      add :code, :text
      add :status, :text
      add :research_complete, :boolean
      add :parent_code, :text
      add :related_adr_codes, {:array, :text}, default: []
      add :adr_codes, {:array, :text}, default: []
      add :feature_code, :text
      add :mode, :text
      add :summary, :text
      add :participants, {:array, :text}, default: []

      add :node_id,
          references(:genesis_nodes,
            column: :id,
            name: "genesis_artifacts_node_id_fkey",
            type: :uuid
          ),
          null: false

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_artifacts, [:node_id])
    create index(:genesis_artifacts, [:node_id, :kind])

    create table(:genesis_roadmap_items, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :kind, :text, null: false
      add :number, :bigint, null: false
      add :title, :text, null: false
      add :status, :text, null: false
      add :governed_by, {:array, :text}, default: []
      add :goals, {:array, :text}, default: []
      add :goal, :text
      add :parent_uc, :text
      add :allowed_files, {:array, :text}, default: []
      add :blocked_by, {:array, :text}, default: []
      add :steps, {:array, :text}, default: []
      add :done_when, :text
      add :owner, :text

      add :node_id,
          references(:genesis_nodes,
            column: :id,
            name: "genesis_roadmap_items_node_id_fkey",
            type: :uuid
          ),
          null: false

      add :parent_id,
          references(:genesis_roadmap_items,
            column: :id,
            name: "genesis_roadmap_items_parent_id_fkey",
            type: :uuid
          )

      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_roadmap_items, [:node_id])
    create index(:genesis_roadmap_items, [:parent_id])
    create index(:genesis_roadmap_items, [:node_id, :kind])
  end

  def down do
    drop table(:genesis_roadmap_items)
    drop table(:genesis_artifacts)
  end
end
