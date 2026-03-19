defmodule Ichor.Gateway.CronJob do
  @moduledoc """
  Ash Resource for scheduled cron jobs stored in the `cron_jobs` SQLite table.

  Stores one-time or recurring jobs that fire at `next_fire_at`.
  Signals are emitted via `Ichor.Signals.FromAsh` on schedule and reschedule.
  """

  use Ash.Resource,
    domain: Ichor.Control,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh],
    primary_read_warning?: false

  sqlite do
    repo(Ichor.Repo)
    table("cron_jobs")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :agent_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :payload, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :next_fire_at, :utc_datetime do
      allow_nil?(false)
      public?(true)
    end

    attribute :is_one_time, :boolean do
      default(true)
      allow_nil?(false)
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  actions do
    create :schedule_once do
      primary?(true)
      accept([:agent_id, :payload, :next_fire_at, :is_one_time])
    end

    read :for_agent do
      argument(:agent_id, :string, allow_nil?: false)
      filter(expr(agent_id == ^arg(:agent_id)))
    end

    read :all_scheduled do
      primary?(true)
      prepare(build(sort: [next_fire_at: :asc]))
    end

    read :due do
      argument(:now, :utc_datetime, allow_nil?: false)
      filter(expr(next_fire_at <= ^arg(:now)))
      prepare(build(sort: [next_fire_at: :asc]))
    end

    update :reschedule do
      argument(:next_fire_at, :utc_datetime, allow_nil?: false)
      change(set_attribute(:next_fire_at, arg(:next_fire_at)))
    end

    destroy :complete do
      primary?(true)
    end
  end

  code_interface do
    define(:schedule_once, args: [:agent_id, :payload, :next_fire_at])
    define(:for_agent, args: [:agent_id])
    define(:all_scheduled)
    define(:due, args: [:now])
    define(:get, action: :all_scheduled, get_by: [:id])
    define(:reschedule, args: [:next_fire_at])
    define(:complete)
  end
end
