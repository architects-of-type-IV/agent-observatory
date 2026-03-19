defmodule Ichor.Mesh.DecisionLogTest do
  use ExUnit.Case, async: true

  alias Ichor.Mesh.DecisionLog

  test "from_json builds a decision log from valid attrs" do
    attrs = %{
      "meta" => %{
        "trace_id" => "trace-1",
        "timestamp" => "2026-03-18T10:00:00Z"
      },
      "identity" => %{
        "agent_id" => "agent-1",
        "agent_type" => "planner",
        "capability_version" => "2.4.0"
      },
      "cognition" => %{
        "intent" => "draft_plan"
      },
      "action" => %{
        "status" => "success"
      }
    }

    assert {:ok, %DecisionLog{} = log} = DecisionLog.from_json(attrs)
    assert log.meta.trace_id == "trace-1"
    assert log.identity.agent_id == "agent-1"
    assert DecisionLog.major_version(log) == 2
    assert DecisionLog.root?(log)
  end

  test "root?/1 is true when parent_step_id is nil" do
    log = %DecisionLog{
      meta: %DecisionLog.Meta{parent_step_id: nil}
    }

    assert DecisionLog.root?(log)
  end
end
