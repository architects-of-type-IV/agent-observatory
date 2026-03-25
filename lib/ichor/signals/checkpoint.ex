defmodule Ichor.Signals.Checkpoint do
  @moduledoc """
  Tracks the last processed event position per signal module and key.

  Used by ADR-026 projectors to resume from a known position after restart,
  avoiding full event log replay.
  """

  use Ash.Resource,
    domain: Ichor.Signals,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo(Ichor.Repo)
    table("signal_checkpoints")
  end

  identities do
    identity(:module_key, [:signal_module, :key])
  end

  attributes do
    uuid_primary_key(:id)

    attribute :signal_module, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :key, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute(:last_event_id, :string, public?: true)

    attribute :last_event_occurred_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute(:event_count, :integer, allow_nil?: false, default: 0, public?: true)
    attribute(:last_signal_emitted_at, :utc_datetime_usec, public?: true)

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([:signal_module, :key, :last_event_id, :last_event_occurred_at, :event_count])
      upsert?(true)
      upsert_identity(:module_key)
    end

    update :advance do
      accept([:last_event_id, :last_event_occurred_at])
      change(atomic_update(:event_count, expr(event_count + 1)))
    end

    update :mark_emitted do
      accept([])
      change(set_attribute(:last_signal_emitted_at, expr(now())))
    end

    read :for_module do
      argument(:signal_module, :string, allow_nil?: false)
      filter(expr(signal_module == ^arg(:signal_module)))
    end

    read :for_resume do
      argument(:signal_module, :string, allow_nil?: false)
      argument(:key, :string, allow_nil?: false)
      filter(expr(signal_module == ^arg(:signal_module) and key == ^arg(:key)))
    end
  end

  code_interface do
    define(:create)
    define(:advance)
    define(:mark_emitted)
    define(:for_module, args: [:signal_module])
    define(:for_resume, args: [:signal_module, :key])
  end
end
