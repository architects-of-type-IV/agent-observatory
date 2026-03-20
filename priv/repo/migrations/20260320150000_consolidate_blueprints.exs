defmodule Ichor.Repo.Migrations.ConsolidateBlueprints do
  @moduledoc """
  Collapses workshop_team_blueprints + 3 child tables into a single
  workshop_blueprints table with embedded JSON columns for agents,
  spawn_links, and comm_rules.

  Data migration: reads existing rows and re-encodes them into the new
  embedded JSON columns before dropping the old tables.
  """

  use Ecto.Migration

  def up do
    create table(:workshop_blueprints, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :strategy, :text, null: false
      add :default_model, :text, null: false
      add :cwd, :text
      add :agents, :text, null: false, default: "[]"
      add :spawn_links, :text, null: false, default: "[]"
      add :comm_rules, :text, null: false, default: "[]"
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:workshop_blueprints, [:name],
             name: "workshop_blueprints_unique_name_index"
           )

    flush()

    migrate_existing_data()

    drop_old_tables()
  end

  def down do
    create table(:workshop_team_blueprints, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :name, :text, null: false
      add :strategy, :text, null: false
      add :default_model, :text, null: false
      add :cwd, :text
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:workshop_team_blueprints, [:name],
             name: "workshop_team_blueprints_unique_name_index"
           )

    create table(:workshop_agent_blueprints, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :team_blueprint_id,
          references(:workshop_team_blueprints,
            column: :id,
            name: "workshop_agent_blueprints_team_blueprint_id_fkey",
            type: :uuid
          ),
          null: false

      add :slot, :bigint, null: false
      add :name, :text, null: false
      add :capability, :text, null: false
      add :model, :text, null: false
      add :permission, :text, null: false
      add :persona, :text
      add :file_scope, :text
      add :quality_gates, :text
      add :canvas_x, :bigint, null: false
      add :canvas_y, :bigint, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:workshop_spawn_links, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :team_blueprint_id,
          references(:workshop_team_blueprints,
            column: :id,
            name: "workshop_spawn_links_team_blueprint_id_fkey",
            type: :uuid
          ),
          null: false

      add :from_slot, :bigint, null: false
      add :to_slot, :bigint, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:workshop_comm_rules, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :team_blueprint_id,
          references(:workshop_team_blueprints,
            column: :id,
            name: "workshop_comm_rules_team_blueprint_id_fkey",
            type: :uuid
          ),
          null: false

      add :from_slot, :bigint, null: false
      add :to_slot, :bigint, null: false
      add :policy, :text, null: false
      add :via_slot, :bigint
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    drop_if_exists table(:workshop_blueprints)
  end

  defp migrate_existing_data do
    # Fetch all existing blueprints with their related rows.
    # We use raw SQL since the old Ash resources are gone.
    blueprints =
      repo().query!(
        "SELECT id, name, strategy, default_model, cwd, inserted_at, updated_at FROM workshop_team_blueprints"
      ).rows

    for [id, name, strategy, default_model, cwd, inserted_at, updated_at] <- blueprints do
      agents =
        repo().query!(
          "SELECT slot, name, capability, model, permission, persona, file_scope, quality_gates, canvas_x, canvas_y FROM workshop_agent_blueprints WHERE team_blueprint_id = ?",
          [id]
        ).rows
        |> Enum.map(fn [slot, a_name, cap, model, perm, persona, fs, qg, cx, cy] ->
          %{
            "slot" => slot,
            "name" => a_name,
            "capability" => cap,
            "model" => model,
            "permission" => perm,
            "persona" => persona || "",
            "file_scope" => fs || "",
            "quality_gates" => qg || "",
            "canvas_x" => cx,
            "canvas_y" => cy
          }
        end)

      spawn_links =
        repo().query!(
          "SELECT from_slot, to_slot FROM workshop_spawn_links WHERE team_blueprint_id = ?",
          [id]
        ).rows
        |> Enum.map(fn [from, to] -> %{"from_slot" => from, "to_slot" => to} end)

      comm_rules =
        repo().query!(
          "SELECT from_slot, to_slot, policy, via_slot FROM workshop_comm_rules WHERE team_blueprint_id = ?",
          [id]
        ).rows
        |> Enum.map(fn [from, to, policy, via] ->
          %{"from_slot" => from, "to_slot" => to, "policy" => policy, "via_slot" => via}
        end)

      repo().query!(
        """
        INSERT INTO workshop_blueprints
          (id, name, strategy, default_model, cwd, agents, spawn_links, comm_rules, inserted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
          id,
          name,
          strategy,
          default_model,
          cwd || "",
          Jason.encode!(agents),
          Jason.encode!(spawn_links),
          Jason.encode!(comm_rules),
          inserted_at,
          updated_at
        ]
      )
    end
  end

  defp drop_old_tables do
    # SQLite does not support dropping foreign key constraints via ALTER TABLE,
    # so we recreate the child tables without them before dropping.
    execute("DROP TABLE IF EXISTS workshop_agent_blueprints")
    execute("DROP TABLE IF EXISTS workshop_spawn_links")
    execute("DROP TABLE IF EXISTS workshop_comm_rules")
    execute("DROP TABLE IF EXISTS workshop_team_blueprints")
  end
end
