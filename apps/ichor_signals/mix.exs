defmodule IchorSignals.MixProject do
  use Mix.Project

  def project do
    [
      app: :ichor_signals,
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
      {:ash, "~> 3.0"},
      {:phoenix, "~> 1.8.3"},
      {:ichor_contracts, path: "../../subsystems/ichor_contracts"}
    ]
  end
end
