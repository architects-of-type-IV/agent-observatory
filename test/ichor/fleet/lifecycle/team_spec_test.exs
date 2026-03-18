defmodule Ichor.Fleet.Lifecycle.TeamSpecTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.Lifecycle.TeamSpec

  test "captures explicit team launch state" do
    agent =
      AgentSpec.new(%{
        name: "lead",
        window_name: "lead",
        agent_id: "mes-123-lead",
        capability: "lead",
        cwd: "/tmp/project",
        team_name: "mes-123",
        session: "mes-123"
      })

    spec =
      TeamSpec.new(%{
        team_name: "mes-123",
        session: "mes-123",
        cwd: "/tmp/project",
        agents: [agent],
        prompt_dir: "/tmp/prompts"
      })

    assert spec.team_name == "mes-123"
    assert [%AgentSpec{name: "lead"}] = spec.agents
  end
end
