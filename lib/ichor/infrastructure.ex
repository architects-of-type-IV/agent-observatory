defmodule Ichor.Infrastructure do
  @moduledoc """
  Namespace for non-domain infrastructure concerns.

  This is where runtime adapters and host integrations should move when they
  do not model product concepts. Typical examples are tmux, MCP transport,
  process orchestration, file sync boundaries, and external service adapters.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Infrastructure.Operations)
    resource(Ichor.Infrastructure.WebhookDelivery)
    resource(Ichor.Infrastructure.TmuxOperations)
    resource(Ichor.Infrastructure.MemoriesOperations)
    resource(Ichor.Infrastructure.WebhookOperations)
  end

  tools do
    tool(:system_health, Ichor.Infrastructure.Operations, :system_health)
    tool(:tmux_sessions, Ichor.Infrastructure.Operations, :tmux_sessions)
    tool(:sweep, Ichor.Infrastructure.Operations, :sweep)
    tool(:tmux_list_sessions, Ichor.Infrastructure.TmuxOperations, :list_sessions)
    tool(:tmux_list_panes, Ichor.Infrastructure.TmuxOperations, :list_panes)
    tool(:tmux_capture_pane, Ichor.Infrastructure.TmuxOperations, :capture_pane)
    tool(:tmux_send_keys, Ichor.Infrastructure.TmuxOperations, :send_keys)
    tool(:memories_search, Ichor.Infrastructure.MemoriesOperations, :search)
    tool(:memories_ingest, Ichor.Infrastructure.MemoriesOperations, :ingest)
    tool(:memories_query, Ichor.Infrastructure.MemoriesOperations, :query)
    tool(:webhook_deliver, Ichor.Infrastructure.WebhookOperations, :deliver)
  end
end
