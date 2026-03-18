defmodule Ichor.Fleet.Lifecycle.AgentSpecTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.Lifecycle.AgentSpec

  test "builds a runtime spec with defaults" do
    spec =
      AgentSpec.new(%{
        name: "builder",
        window_name: "builder-1",
        agent_id: "builder-1",
        cwd: "/tmp/project",
        session: "ichor-fleet"
      })

    assert spec.name == "builder"
    assert spec.capability == "builder"
    assert spec.model == "sonnet"
    assert spec.metadata == %{}
  end
end
