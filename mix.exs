defmodule CronScheduler.MixProject do
  use Mix.Project

  def project do
    [
      app: :cron_scheduler,
      version: "0.1.0",
      # Requires the built-in JSON module (Elixir 1.18+) for payload encoding,
      # which is what keeps this project dependency-free.
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Durable one-off and recurring job scheduling over pluggable store and queue.",
      docs: [main: "CronScheduler"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    []
  end
end
