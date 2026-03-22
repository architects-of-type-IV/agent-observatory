defmodule Ichor.Repo.Migrations.DropOrphanedTables do
  use Ecto.Migration

  @disable_ddl_transaction true

  def change do
    # Sprint 5 legacy tables (superseded by Ash resources or ETS)
    drop_if_exists table(:events)
    drop_if_exists table(:sessions)
    drop_if_exists table(:token_usages)
    drop_if_exists table(:tasks)
    drop_if_exists table(:notes)
    drop_if_exists table(:messages)

    # Heartbeat table (resource moved to tmp/trash/dead-code)
    drop_if_exists table(:gateway_heartbeats)

    # MES projects (data migrated to :projects in reshape migration)
    drop_if_exists table(:mes_projects)

    # Genesis tables -- children first (FK: subtasks -> tasks -> sections -> phases -> nodes)
    drop_if_exists table(:genesis_subtasks)
    drop_if_exists table(:genesis_tasks)
    drop_if_exists table(:genesis_sections)
    drop_if_exists table(:genesis_phases)

    # Genesis tables referencing genesis_nodes
    drop_if_exists table(:genesis_adrs)
    drop_if_exists table(:genesis_features)
    drop_if_exists table(:genesis_use_cases)
    drop_if_exists table(:genesis_checkpoints)
    drop_if_exists table(:genesis_conversations)
    drop_if_exists table(:genesis_artifacts)
    drop_if_exists table(:genesis_roadmap_items)

    # Genesis parent (all FK dependents dropped above)
    drop_if_exists table(:genesis_nodes)
  end
end
