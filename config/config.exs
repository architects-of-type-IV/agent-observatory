# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ichor,
  generators: [timestamp_type: :utc_datetime],
  ecto_repos: [Ichor.Repo],
  ash_domains: [
    Ichor.SignalBus,
    Ichor.Workshop,
    Ichor.Archon,
    Ichor.Infrastructure,
    Ichor.Factory
  ]

config :ichor, Ichor.Repo,
  database: Path.expand("../ichor_dev.db", __DIR__),
  pool_size: 5

# Ichor Contracts -- signals runtime implementation
config :ichor_contracts, :signals_impl, Ichor.Signals.Runtime

# Configure the endpoint
config :ichor, IchorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: IchorWeb.ErrorHTML, json: IchorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ichor.PubSub,
  live_view: [signing_salt: "Uss9/vBE"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  ichor: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  ichor: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Memories knowledge graph API (fleet-wide access)
config :ichor, :memories,
  url: "http://localhost:4000",
  api_key: "mem_bClhCPVjvDOW9StxLVHHc6zVoYlaYYxU2NS7i4LlTI4dlqanqPThYevtRz4rpT4C3_d5E10",
  group_id: "0f8eae17-15fc-5af1-8761-0093dc9b5027",
  user_id: "8fe50fd6-f0da-5adc-9251-6417dc3092e8"

# Oban background job processing
config :ichor, Oban,
  repo: Ichor.Repo,
  notifier: Oban.Notifiers.PG,
  peer: Oban.Peers.Global,
  prefix: false,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Ichor.Factory.Workers.MesTick}
     ]}
  ],
  queues: [
    webhooks: 10,
    quality_gate: 4,
    memories: 2,
    maintenance: 1,
    scheduled: 2
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
