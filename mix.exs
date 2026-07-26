defmodule TmuxChannel.MixProject do
  use Mix.Project

  def project do
    [
      app: :tmux_channel,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Message delivery and pane capture for agents running in tmux.",
      docs: [main: "TmuxChannel"]
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
