defmodule Ichor.Fleet do
  @moduledoc """
  Session management domain.

  Owns the runtime lifecycle of AI agent sessions (Claude, Gemini, Codex)
  and their grouping into teams. Workshop defines the blueprints;
  Fleet manages the running instances.
  """

  use Ash.Domain

  resources do
    resource Ichor.Fleet.Session do
      define(:list_sessions, action: :list)
      define(:active_sessions, action: :active)
      define(:spawn_session, action: :spawn, args: [:name])
      define(:stop_session, action: :stop, args: [:session])
    end
  end
end
