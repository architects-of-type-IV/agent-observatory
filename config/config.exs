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
    Ichor.Signals,
    Ichor.Workshop,
    Ichor.Archon,
    Ichor.Infrastructure,
    Ichor.Factory,
    Ichor.Settings
  ]

config :ichor, Ichor.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: 5434,
  database: "ichor_dev",
  pool_size: 20

# Signals runtime implementation
config :ichor, :signals_impl, Ichor.Signals.Runtime

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
  api_key: "mem_ef5owe6C1muIiXH7vHGIAiSih2nzWrURCQ4Bd4XmpwWetjdDm42kdTLKXeJY1SsaR_bqkqqJ",
  group_id: "019ce2b5-7ed0-71ec-b831-36ea37d2ef6b",
  user_id: "8c5d6f57-443f-42be-9700-f996fb11719f"

# Oban background job processing
config :ichor, Oban,
  engine: Oban.Engines.Basic,
  repo: Ichor.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Ichor.Factory.Workers.MesTick},
       {"* * * * *", Ichor.Factory.Workers.HealthCheckWorker},
       {"* * * * *", Ichor.Factory.Workers.ProjectDiscoveryWorker},
       {"*/5 * * * *", Ichor.Factory.Workers.OrphanSweepWorker},
       {"*/5 * * * *", Ichor.Factory.Workers.PipelineReconcilerWorker}
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
