defmodule IchorMesh.MixProject do
  use Mix.Project

  def project do
    [
      app: :ichor_mesh,
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
      {:ecto, "~> 3.13"},
      {:ichor_signals, in_umbrella: true}
    ]
  end
end
