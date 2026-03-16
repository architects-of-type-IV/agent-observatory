defmodule Ichor.Repo.Migrations.CreateGenesisCheckpointsAndConversations do
  use Ecto.Migration

  def up do
    create table(:genesis_checkpoints, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :title, :text, null: false
      add :mode, :text, null: false
      add :content, :text
      add :summary, :text
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_checkpoints, [:node_id])

    create table(:genesis_conversations, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :title, :text, null: false
      add :mode, :text, null: false
      add :content, :text
      add :participants, {:array, :text}, default: []
      add :node_id, references(:genesis_nodes, type: :uuid), null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create index(:genesis_conversations, [:node_id])
  end

  def down do
    drop table(:genesis_conversations)
    drop table(:genesis_checkpoints)
  end
end
