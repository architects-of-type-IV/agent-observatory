defmodule Signals.MixProject do
  use Mix.Project

  def project do
    [
      app: :signals,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description:
        "Signals: stateful accumulators that correlate unrelated events into conclusions.",
      docs: [main: "Signals"]
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [{:gen_stage, "~> 1.2", optional: true}]
  end
end
