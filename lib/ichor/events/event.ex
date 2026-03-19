defmodule Ichor.Events.Event do
  @moduledoc false
  use Ash.Resource,
    domain: Ichor.Observability,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Ichor.Repo)
    table("events")
  end

  attributes do
    uuid_primary_key(:id)

    attribute :source_app, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :session_id, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :hook_event_type, Ichor.Events.Types.HookEventType do
      allow_nil?(false)
      public?(true)
    end

    attribute :payload, :map do
      allow_nil?(false)
      default(%{})
      public?(true)
    end

    attribute(:summary, :string, public?: true)
    attribute(:model_name, :string, public?: true)
    attribute(:tool_name, :string, public?: true)
    attribute(:tool_use_id, :string, public?: true)
    attribute(:cwd, :string, public?: true)
    attribute(:permission_mode, :string, public?: true)
    attribute(:duration_ms, :integer, public?: true)
    attribute(:tmux_session, :string, public?: true)

    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([
        :source_app,
        :session_id,
        :hook_event_type,
        :payload,
        :summary,
        :model_name,
        :tool_name,
        :tool_use_id,
        :cwd,
        :permission_mode,
        :duration_ms,
        :tmux_session
      ])
    end
  end

  code_interface do
    define(:read)
  end
end
