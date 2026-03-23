defmodule Ichor.Repo.Migrations.WorkshopCrud do
  @moduledoc """
  Adds new fields to Workshop resources for full CRUD support.

  Changes:
  - workshop_agent_types: adds description, default_provider, system_prompt
  - workshop_agents: adds role, cwd (new persisted agent resource fields)
  - workshop_prompts: adds category
  - workshop_teams: agents column already exists in DB; skipped
  """

  use Ecto.Migration

  def up do
    alter table(:workshop_prompts) do
      add :category, :text
    end

    alter table(:workshop_agents) do
      add :role, :text
      add :cwd, :text, default: "", null: false
    end

    alter table(:workshop_agent_types) do
      add :description, :text
      add :default_provider, :text
      add :system_prompt, :text
    end
  end

  def down do
    alter table(:workshop_agent_types) do
      remove :system_prompt
      remove :default_provider
      remove :description
    end

    alter table(:workshop_agents) do
      remove :cwd
      remove :role
    end

    alter table(:workshop_prompts) do
      remove :category
    end
  end
end
