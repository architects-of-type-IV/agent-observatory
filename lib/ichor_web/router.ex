defmodule IchorWeb.Router do
  use IchorWeb, :router

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

  pipeline :hitl_auth do
    plug Ichor.Plugs.OperatorAuth
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
    post "/debug/hitl-clear", DebugController, :hitl_clear
    post "/debug/purge", DebugController, :purge
    post "/debug/mes-cleanup", DebugController, :mes_cleanup
    get "/debug/mes-signals", DebugController, :mes_signals
  end

  scope "/gateway", IchorWeb do
    pipe_through :api
    post "/messages", GatewayController, :create
    post "/heartbeat", HeartbeatController, :create
    post "/webhooks/:webhook_id", WebhookController, :create
    post "/rpc", GatewayRpcController, :create
  end

  scope "/gateway/sessions/:session_id", IchorWeb do
    pipe_through [:api, :hitl_auth]

    post "/pause", HITLController, :pause
    post "/unpause", HITLController, :unpause
    post "/rewrite", HITLController, :rewrite
    post "/inject", HITLController, :inject
  end

  forward "/mcp", AshAi.Mcp.Router,
    tools: [
      :check_inbox,
      :acknowledge_message,
      :send_message,
      :get_tasks,
      :update_task_status,
      :spawn_agent,
      :stop_agent,
      :create_agent,
      :list_agents,
      :read_memory,
      :memory_replace,
      :memory_insert,
      :memory_rethink,
      :conversation_search,
      :conversation_search_date,
      :archival_memory_insert,
      :archival_memory_search,
      :create_genesis_node,
      :advance_node,
      :list_genesis_nodes,
      :get_genesis_node,
      :gate_check,
      :create_adr,
      :update_adr,
      :list_adrs,
      :create_feature,
      :list_features,
      :create_use_case,
      :list_use_cases,
      :create_checkpoint,
      :create_conversation,
      :list_conversations,
      :create_phase,
      :create_section,
      :create_task,
      :create_subtask,
      :list_phases,
      :next_jobs,
      :claim_job,
      :complete_job,
      :fail_job,
      :get_run_status,
      :load_jsonl,
      :export_jsonl
    ],
    otp_app: :ichor

  # Silence Chrome DevTools probe
  get "/.well-known/*path", IchorWeb.NoopController, :noop

  scope "/", IchorWeb do
    pipe_through :browser

    live "/", DashboardLive
    live "/:view", DashboardLive
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
