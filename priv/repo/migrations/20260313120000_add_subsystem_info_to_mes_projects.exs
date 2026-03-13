defmodule Ichor.Repo.Migrations.AddSubsystemInfoToMesProjects do
  @moduledoc """
  Adds self-describing subsystem fields to mes_projects, matching
  the Ichor.Mes.Subsystem.Info struct contract.
  """

  use Ecto.Migration

  def up do
    alter table(:mes_projects) do
      add :topic, :text
      add :version, :text, default: "0.1.0"
      add :features, :text
      add :use_cases, :text
      add :architecture, :text
      add :dependencies, :text
      add :signals_emitted, :text
      add :signals_subscribed, :text
    end
  end

  def down do
    alter table(:mes_projects) do
      remove :topic
      remove :version
      remove :features
      remove :use_cases
      remove :architecture
      remove :dependencies
      remove :signals_emitted
      remove :signals_subscribed
    end
  end
end
