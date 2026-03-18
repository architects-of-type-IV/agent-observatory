defmodule Ichor.Repo.Migrations.CreateMesProjects do
  @moduledoc """
  Creates the mes_projects table for the Manufacturing Execution System.
  """

  use Ecto.Migration

  def up do
    create table(:mes_projects, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :title, :text, null: false
      add :description, :text, null: false
      add :subsystem, :text, null: false
      add :signal_interface, :text, null: false
      add :status, :text, null: false, default: "proposed"
      add :team_name, :text
      add :run_id, :text
      add :picked_up_by, :text
      add :picked_up_at, :utc_datetime_usec
      add :path, :text
      add :build_log, :text
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
  end

  def down do
    drop table(:mes_projects)
  end
end
