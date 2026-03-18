[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["apps/*"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{ex,exs}", "config/*.exs"]
]
