defmodule IchorEvents.MixProject do
  use Mix.Project

  def project do
    [
      app: :ichor_events,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ichor_data, in_umbrella: true},
      {:ash, "~> 3.0"},
      {:ash_sqlite, "~> 0.2"}
    ]
  end
end
