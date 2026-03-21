import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :ichor, Ichor.Repo,
  database: Path.expand("../ichor_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :ichor, IchorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "aBlgLUb/veilHX83O3xEkTTRJ7etTmP2+HpA2B8r0Qr/sdZs1l5MS/0Y6PfehObb",
  server: false

# Ash: disable async for SQLite single-writer constraint
config :ash, :disable_async?, true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Oban inline testing -- jobs run synchronously, no queues needed
config :ichor, Oban, testing: :inline

# Disable swoosh api client in test; production uses Req explicitly.
config :swoosh, :api_client, false
