defmodule Ichor.Infrastructure.WebhookDelivery do
  @moduledoc "Webhook delivery tracking with retry and dead-letter lifecycle."

  use Ash.Resource,
    domain: Ichor.Infrastructure,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("webhook_deliveries")
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:target_url, :string, allow_nil?: false, public?: true)
    attribute(:payload, :string, allow_nil?: false, public?: true)
    attribute(:signature, :string, public?: true)

    attribute :status, :atom do
      constraints(one_of: [:pending, :delivered, :failed, :dead])
      default(:pending)
      public?(true)
    end

    attribute(:attempt_count, :integer, default: 0, public?: true)
    attribute(:next_retry_at, :utc_datetime, public?: true)
    attribute(:agent_id, :string, allow_nil?: false, public?: true)
    attribute(:webhook_id, :string, public?: true)

    create_timestamp(:inserted_at)
  end

  actions do
    defaults([:read])

    create :enqueue do
      accept([:target_url, :payload, :signature, :agent_id, :webhook_id])
      change(set_attribute(:next_retry_at, &__MODULE__.now/0))
    end

    read :get do
      get_by([:id])
    end

    read :due_for_delivery do
      prepare(build(sort: [next_retry_at: :asc], limit: 5))
      filter(expr(status in [:pending, :failed] and next_retry_at <= now()))
    end

    read :dead_letters_for_agent do
      argument(:agent_id, :string, allow_nil?: false)
      filter(expr(agent_id == ^arg(:agent_id) and status == :dead))
    end

    read :all_dead_letters do
      filter(expr(status == :dead))
    end

    update :mark_delivered do
      change(set_attribute(:status, :delivered))
    end

    update :schedule_retry do
      accept([:next_retry_at, :attempt_count])
      change(set_attribute(:status, :failed))
    end

    update :mark_dead do
      accept([:attempt_count])
      change(set_attribute(:status, :dead))
    end
  end

  code_interface do
    define(:enqueue, args: [:target_url, :payload, :signature, :agent_id])
    define(:get, action: :get, args: [:id])
    define(:due_for_delivery)
    define(:dead_letters_for_agent, args: [:agent_id])
    define(:all_dead_letters)
    define(:mark_delivered)
    define(:schedule_retry)
    define(:mark_dead)
  end

  @doc false
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
