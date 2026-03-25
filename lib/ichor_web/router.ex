defmodule IchorWeb.Router do
  @moduledoc "Phoenix router — maps all HTTP and LiveView routes for the Ichor web application."

  use IchorWeb, :router

  alias Ichor.McpProfiles, as: Profiles

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IchorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", IchorWeb do
    pipe_through :api

    post "/events", EventController, :create
    get "/debug/registry", DebugController, :registry
    get "/debug/health", DebugController, :health
    get "/debug/traces", DebugController, :traces
    get "/debug/mailboxes", DebugController, :mailboxes
    get "/debug/tmux", DebugController, :tmux
    get "/debug/fleet-agents", DebugController, :fleet_agents
    post "/debug/purge", DebugController, :purge
    post "/debug/mes-cleanup", DebugController, :mes_cleanup
    get "/debug/mes-signals", DebugController, :mes_signals
  end

  scope "/gateway", IchorWeb do
    pipe_through :api
    post "/heartbeat", HeartbeatController, :create
    post "/webhooks/:webhook_id", WebhookController, :create
    post "/rpc", GatewayRpcController, :create
  end

  forward "/mcp/archon", AshAi.Mcp.Router,
    tools: Profiles.archon(),
    otp_app: :ichor

  forward "/mcp", AshAi.Mcp.Router,
    tools: Profiles.agent(),
    otp_app: :ichor

  # Silence Chrome DevTools probe
  get "/.well-known/*path", IchorWeb.NoopController, :noop

  scope "/", IchorWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/:view", DashboardLive
    live "/:view/:category", DashboardLive
    get "/export/events", ExportController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ichor, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: IchorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
