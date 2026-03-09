defmodule Ichor.Repo.Migrations.CreateTokenUsages do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:token_usages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :session_id, :string, null: false
      add :source_app, :string, null: false
      add :model_name, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :cache_read_tokens, :integer, null: false, default: 0
      add :cache_write_tokens, :integer, null: false, default: 0
      add :estimated_cost_cents, :integer, null: false, default: 0
      add :tool_name, :string

      timestamps()
    end

    create_if_not_exists index(:token_usages, [:session_id])
    create_if_not_exists index(:token_usages, [:model_name])
  end
end
