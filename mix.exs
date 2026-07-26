defmodule HostRegistry.MixProject do
  use Mix.Project

  def project do
    [
      app: :host_registry,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Tracks the BEAM nodes available to run work, with cluster-wide visibility.",
      docs: [main: "HostRegistry"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end
