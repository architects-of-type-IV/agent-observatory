defmodule ObservatoryWeb.Router do
  use ObservatoryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {ObservatoryWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ObservatoryWeb do
    pipe_through :api

    post "/events", EventController, :create
  end

  scope "/", ObservatoryWeb do
    pipe_through :browser

    live "/", DashboardLive
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:observatory, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: ObservatoryWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
