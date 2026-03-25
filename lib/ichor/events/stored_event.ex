defmodule Ichor.Events.StoredEvent do
  @moduledoc """
  Append-only durable event log. Stores every domain event for replay and audit.

  Signal bridge events (source: :signal_bridge) are excluded from persistence
  to avoid noise in the log.
  """

  use Ash.Resource,
    domain: Ichor.Events,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo(Ichor.Repo)
    table("stored_events")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :topic, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :key, :string do
      public?(true)
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil?(false)
      public?(true)
    end

    attribute(:causation_id, :string, public?: true)
    attribute(:correlation_id, :string, public?: true)
    attribute(:data, :map, allow_nil?: false, default: %{}, public?: true)
    attribute(:metadata, :map, allow_nil?: false, default: %{}, public?: true)

    create_timestamp(:inserted_at)
  end

  actions do
    defaults([:read])

    create :record do
      accept([:topic, :key, :occurred_at, :causation_id, :correlation_id, :data, :metadata])
    end

    read :by_topic do
      argument(:topic, :string, allow_nil?: false)
      filter(expr(topic == ^arg(:topic)))
      prepare(build(sort: [occurred_at: :asc]))
    end

    read :by_key do
      argument(:key, :string, allow_nil?: false)
      filter(expr(key == ^arg(:key)))
      prepare(build(sort: [occurred_at: :asc]))
    end

    read :since do
      argument(:since, :utc_datetime_usec, allow_nil?: false)
      filter(expr(occurred_at >= ^arg(:since)))
      prepare(build(sort: [occurred_at: :asc]))
    end

    read :for_replay do
      argument(:topics, {:array, :string}, allow_nil?: false)
      argument(:after, :utc_datetime_usec, allow_nil?: false)
      filter(expr(topic in ^arg(:topics) and occurred_at > ^arg(:after)))
      prepare(build(sort: [occurred_at: :asc]))
    end

    destroy :prune do
      argument(:before, :utc_datetime_usec, allow_nil?: false)
      filter(expr(occurred_at < ^arg(:before)))
    end
  end

  code_interface do
    define(:record)
    define(:by_topic, args: [:topic])
    define(:by_key, args: [:key])
    define(:since, args: [:since])
    define(:for_replay, args: [:topics, :after])
  end
end
