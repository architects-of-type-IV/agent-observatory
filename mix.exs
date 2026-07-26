defmodule AgentPromptProtocol.MixProject do
  use Mix.Project

  def project do
    [
      app: :agent_prompt_protocol,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Communication protocol blocks and templating for multi-agent prompts.",
      docs: [main: "AgentPromptProtocol"]
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
