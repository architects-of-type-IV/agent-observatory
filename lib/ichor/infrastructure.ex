defmodule Ichor.Infrastructure do
  @moduledoc """
  Namespace for non-domain infrastructure concerns.

  This is where runtime adapters and host integrations should move when they
  do not model product concepts. Typical examples are tmux, MCP transport,
  process orchestration, file sync boundaries, and external service adapters.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Infrastructure.CronJob)
    resource(Ichor.Infrastructure.HITLInterventionEvent)
    resource(Ichor.Infrastructure.Operations)
    resource(Ichor.Infrastructure.WebhookDelivery)
  end

  tools do
    tool(:system_health, Ichor.Infrastructure.Operations, :system_health)
    tool(:tmux_sessions, Ichor.Infrastructure.Operations, :tmux_sessions)
    tool(:sweep, Ichor.Infrastructure.Operations, :sweep)
  end
end
