defmodule Ichor.Projects.UseCase do
  @moduledoc """
  Use Case with Gherkin scenarios produced during Mode B (Define).

  Each UseCase maps to a Feature and contains structured scenarios
  for validation. Belongs to a Genesis Node.
  """

  use Ash.Resource,
    domain: Ichor.Projects,
    data_layer: AshSqlite.DataLayer,
    simple_notifiers: [Ichor.Signals.FromAsh]

  sqlite do
    repo(Ichor.Repo)
    table("genesis_use_cases")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :code, :string do
      allow_nil?(false)
      public?(true)
      description("UseCase identifier, e.g. UC-0001")
    end

    attribute :title, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :content, :string do
      public?(true)
      description("Full UC body with Gherkin scenarios")
    end

    attribute :feature_code, :string do
      public?(true)
      description("Feature code this UC validates")
    end

    timestamps()
  end

  relationships do
    belongs_to :node, Ichor.Projects.Node do
      allow_nil?(false)
      attribute_public?(true)
    end
  end

  actions do
    defaults([:read, :destroy])

    create :create do
      primary?(true)
      accept([:code, :title, :content, :feature_code, :node_id])
    end

    update :update do
      primary?(true)
      accept([:title, :content, :feature_code])
    end

    read :list_all do
      prepare(build(sort: [inserted_at: :asc]))
    end

    read :by_node do
      argument :node_id, :uuid do
        allow_nil?(false)
      end

      filter(expr(node_id == ^arg(:node_id)))
      prepare(build(sort: [code: :asc]))
    end
  end

  code_interface do
    define(:create)
    define(:update)
    define(:get, action: :read, get_by: [:id])
    define(:list_all)
    define(:by_node, args: [:node_id])
  end
end
