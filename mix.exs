defmodule FleetAnalysis.MixProject do
  use Mix.Project

  def project do
    [
      app: :fleet_analysis,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Health, session, and topology derivation from a fleet's raw event log.",
      docs: [main: "FleetAnalysis"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    []
  end
end
