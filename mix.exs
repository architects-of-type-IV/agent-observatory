defmodule WorkshopCanvas.MixProject do
  use Mix.Project

  def project do
    [
      app: :workshop_canvas,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Pure state transitions for a visual agent-team designer canvas.",
      docs: [main: "WorkshopCanvas"]
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
