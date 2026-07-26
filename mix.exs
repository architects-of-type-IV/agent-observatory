defmodule MemoriesClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :memories_client,
      version: "0.1.0",
      # Requires the built-in JSON module (Elixir 1.18+), which together with
      # OTP's :httpc is what keeps this project dependency-free.
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      description: "Client for the Memories knowledge-graph API.",
      docs: [main: "MemoriesClient"]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    []
  end
end
