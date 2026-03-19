defmodule Ichor.Fleet.RuntimeViewTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.RuntimeView
  alias Ichor.TestSupport.RuntimeViewAgent

  test "resolve_selected_team auto-selects the only team" do
    assert RuntimeView.resolve_selected_team(nil, [%{name: "alpha"}]) == "alpha"
    assert RuntimeView.resolve_selected_team("beta", [%{name: "alpha"}]) == "beta"
    assert RuntimeView.resolve_selected_team(nil, [%{name: "a"}, %{name: "b"}]) == nil
  end

  test "merge_display_teams adds tmux-only team projections" do
    teams = [%{name: "alpha", members: [%{agent_id: "a1"}]}]

    agents = [
      %{
        agent_id: "b1",
        short_name: "lead-b",
        name: "lead-b",
        role: :lead,
        status: :active,
        health: :healthy,
        model: "sonnet",
        cwd: "/tmp/demo",
        channels: %{tmux: "beta"},
        tmux_session: nil
      }
    ]

    projected = RuntimeView.merge_display_teams(teams, agents, ["alpha", "beta", "operator"])

    assert Enum.any?(projected, &(&1.name == "alpha"))
    assert Enum.any?(projected, &(&1.name == "beta"))
    refute Enum.any?(projected, &(&1.name == "operator"))

    beta = Enum.find(projected, &(&1.name == "beta"))
    assert beta.member_count == 1
    assert beta.health == :healthy
    assert [%{agent_id: "b1"}] = beta.members
  end

  test "build_agent_lookup indexes agent by common identities" do
    agent = %RuntimeViewAgent{
      agent_id: "a1",
      session_id: "s1",
      short_name: "alpha",
      team_name: "red",
      cwd: "/tmp/project-x",
      channels: %{tmux: "tmux-a"},
      tmux_session: nil,
      status: :active
    }

    lookup = RuntimeView.build_agent_lookup([agent])

    assert lookup["a1"].team == "red"
    assert lookup["s1"].project == "project-x"
    assert lookup["alpha"].tmux_session == "tmux-a"
  end
end
