defmodule Ichor.Repo.Migrations.CreateGenesisAdrs do
  use Ecto.Migration

  def up do
    create table(:genesis_adrs, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :code, :text, null: false
      add :title, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :content, :text
      add :research_complete, :boolean, default: false
      add :parent_code, :text
      add :related_adr_codes, {:array, :text}, default: []
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_adrs, [:node_id])
  end

  def down do
    drop table(:genesis_adrs)
  end
end
