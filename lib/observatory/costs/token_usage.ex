defmodule Observatory.Costs.TokenUsage do
  use Ash.Resource,
    domain: Observatory.Costs,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Observatory.Repo)
    table("token_usages")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :session_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :source_app, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :model_name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :input_tokens, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :output_tokens, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :cache_read_tokens, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :cache_write_tokens, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :estimated_cost_cents, :integer do
      allow_nil?(false)
      default(0)
      public?(true)
    end

    attribute :tool_name, :string do
      allow_nil?(true)
      public?(true)
    end

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :session_id,
        :source_app,
        :model_name,
        :input_tokens,
        :output_tokens,
        :cache_read_tokens,
        :cache_write_tokens,
        :estimated_cost_cents,
        :tool_name
      ])
    end

    read :by_session do
      argument(:session_id, :string, allow_nil?: false)

      filter(expr(session_id == ^arg(:session_id)))
    end

    read :by_model do
      argument(:model_name, :string, allow_nil?: false)

      filter(expr(model_name == ^arg(:model_name)))
    end

    read :totals do
      prepare(fn query, _context ->
        Ash.Query.load(query, [:total_input_tokens, :total_output_tokens, :total_cost_cents])
      end)
    end
  end

  calculations do
    calculate(:total_input_tokens, :integer, expr(sum(input_tokens)))
    calculate(:total_output_tokens, :integer, expr(sum(output_tokens)))
    calculate(:total_cost_cents, :integer, expr(sum(estimated_cost_cents)))
  end

  identities do
    identity(:unique_token_usage, [:id])
  end
end
