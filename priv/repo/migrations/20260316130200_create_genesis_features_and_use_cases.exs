defmodule Ichor.Repo.Migrations.CreateGenesisFeaturesAndUseCases do
  use Ecto.Migration

  def up do
    create table(:genesis_features, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :code, :text, null: false
      add :title, :text, null: false
      add :content, :text
      add :adr_codes, {:array, :text}, default: []
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_features, [:node_id])

    create table(:genesis_use_cases, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :code, :text, null: false
      add :title, :text, null: false
      add :content, :text
      add :feature_code, :text
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_use_cases, [:node_id])
  end

  def down do
    drop table(:genesis_use_cases)
    drop table(:genesis_features)
  end
end
