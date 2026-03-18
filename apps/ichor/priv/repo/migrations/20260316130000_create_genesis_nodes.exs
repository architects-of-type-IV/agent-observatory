defmodule Ichor.Repo.Migrations.CreateGenesisNodes do
  use Ecto.Migration

  def up do
    create table(:genesis_nodes, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :title, :text, null: false
      add :description, :text, null: false
      add :brief, :text
      add :stakeholders, {:array, :text}, default: []
      add :constraints, {:array, :text}, default: []
      add :status, :text, null: false, default: "discover"
      add :mes_project_id, :uuid
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
  end

  def down do
    drop table(:genesis_nodes)
  end
end
