defmodule Ichor.Signals.HITLInterventionEvent do
  @moduledoc """
  Ash Resource for the `hitl_intervention_events` table.

  Records an audit trail entry each time an operator issues a HITL command
  (pause, unpause, rewrite, inject). Append-only -- no update or destroy actions.
  """

  use Ash.Resource,
    domain: Ichor.Signals,
    data_layer: AshPostgres.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh, Ichor.Events.FromAsh]

  postgres do
    repo(Ichor.Repo)
    table("hitl_intervention_events")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :session_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :agent_id, :string do
      public?(true)
    end

    attribute :operator_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :action, :atom do
      allow_nil?(false)
      constraints(one_of: [:pause, :unpause, :rewrite, :inject])
      public?(true)
    end

    attribute :details, :map do
      default(%{})
      public?(true)
    end

    create_timestamp(:inserted_at)
  end

  actions do
    create :record do
      accept([:session_id, :agent_id, :operator_id, :action, :details])
    end

    read :by_session do
      argument(:session_id, :string, allow_nil?: false)

      filter(expr(session_id == ^arg(:session_id)))
    end

    read :by_agent do
      argument(:agent_id, :string, allow_nil?: false)

      filter(expr(agent_id == ^arg(:agent_id)))
    end

    read :by_operator do
      argument(:operator_id, :string, allow_nil?: false)

      filter(expr(operator_id == ^arg(:operator_id)))
    end

    read :recent do
      prepare(build(sort: [inserted_at: :desc], limit: 100))
    end
  end

  code_interface do
    define(:record, action: :record)
    define(:by_session, action: :by_session, args: [:session_id])
    define(:by_agent, action: :by_agent, args: [:agent_id])
    define(:by_operator, action: :by_operator, args: [:operator_id])
    define(:recent, action: :recent)
  end
end
