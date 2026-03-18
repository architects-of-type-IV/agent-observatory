defmodule Ichor.Fleet.RuntimeQueryTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.RuntimeQuery

  test "find_team_member returns member by agent id" do
    teams = [%{members: [%{agent_id: "a1", name: "lead"}, %{agent_id: "a2", name: "worker"}]}]

    assert %{name: "worker"} = RuntimeQuery.find_team_member(teams, "a2")
    assert RuntimeQuery.find_team_member(teams, "missing") == nil
  end

  test "find_active_task returns in-progress task for owner" do
    swarm = %{
      tasks: [%{status: "pending", owner: "agent-1"}, %{status: "in_progress", owner: "agent-2"}]
    }

    assert %{owner: "agent-2"} = RuntimeQuery.find_active_task("agent-2", swarm)
    assert RuntimeQuery.find_active_task("agent-1", swarm) == nil
  end

  test "format_team projects team for Archon output" do
    team = %{
      name: "alpha",
      members: [%{agent_id: "a1", name: "lead", status: :active}],
      member_count: 1,
      health: "healthy",
      source: :runtime
    }

    projected = RuntimeQuery.format_team(team)

    assert projected["name"] == "alpha"
    assert projected["member_count"] == 1

    assert projected["members"] == [
             %{"session_id" => "a1", "role" => "lead", "status" => :active}
           ]
  end
end
