defmodule Observatory.Events.Event do
  use Ash.Resource,
    domain: Observatory.Events,
    data_layer: AshSqlite.DataLayer

  sqlite do
    repo(Observatory.Repo)
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

    attribute :hook_event_type, :atom do
      allow_nil?(false)
      public?(true)

      constraints(
        one_of: [
          :SessionStart,
          :SessionEnd,
          :UserPromptSubmit,
          :PreToolUse,
          :PostToolUse,
          :PostToolUseFailure,
          :PermissionRequest,
          :Notification,
          :SubagentStart,
          :SubagentStop,
          :Stop,
          :PreCompact
        ]
      )
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
        :duration_ms
      ])
    end
  end

  identities do
    identity(:unique_event, [:id])
  end
end
