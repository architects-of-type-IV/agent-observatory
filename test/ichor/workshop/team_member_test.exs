defmodule Ichor.Workshop.TeamMemberTest do
  @moduledoc false

  use ExUnit.Case, async: false

  alias Ichor.Workshop.{AgentType, Team, TeamMember}

  # Ash string type converts "" to nil by default (allow_empty?: false).
  # extra_instructions, file_scope, and quality_gates all have default("") +
  # allow_nil?(false), meaning they must be supplied explicitly with non-empty
  # values. We use a shared helper to provide the minimum valid create params.
  defp base_params(team_id, slot, name, overrides \\ %{}) do
    Map.merge(
      %{
        team_id: team_id,
        slot: slot,
        name: name,
        extra_instructions: "none",
        file_scope: ".",
        quality_gates: "mix compile"
      },
      overrides
    )
  end

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Ichor.Repo)
    {:ok, team} = Team.create(%{name: "tm-team-#{System.unique_integer([:positive])}"})
    %{team: team}
  end

  describe "create" do
    test "creates a team member with valid team_id and required fields", %{team: team} do
      assert {:ok, member} =
               TeamMember.create(base_params(team.id, 1, "Agent Alpha"))

      assert member.team_id == team.id
      assert member.slot == 1
      assert member.name == "Agent Alpha"
    end

    test "applies capability default", %{team: team} do
      assert {:ok, member} = TeamMember.create(base_params(team.id, 2, "A"))
      assert member.capability == "builder"
    end

    test "applies model default", %{team: team} do
      assert {:ok, member} = TeamMember.create(base_params(team.id, 3, "A"))
      assert member.model == "sonnet"
    end

    test "applies permission default", %{team: team} do
      assert {:ok, member} = TeamMember.create(base_params(team.id, 4, "A"))
      assert member.permission == "default"
    end

    test "applies canvas position defaults", %{team: team} do
      assert {:ok, member} = TeamMember.create(base_params(team.id, 5, "A"))
      assert member.canvas_x == 40
      assert member.canvas_y == 30
    end

    test "accepts all optional fields", %{team: team} do
      assert {:ok, member} =
               TeamMember.create(%{
                 team_id: team.id,
                 slot: 6,
                 name: "Full Agent",
                 capability: "reviewer",
                 model: "opus",
                 permission: "readonly",
                 extra_instructions: "Be strict.",
                 file_scope: "lib/",
                 quality_gates: "mix test",
                 tool_scope: ["Read", "Grep"],
                 canvas_x: 100,
                 canvas_y: 200
               })

      assert member.capability == "reviewer"
      assert member.model == "opus"
      assert member.permission == "readonly"
      assert member.extra_instructions == "Be strict."
      assert member.file_scope == "lib/"
      assert member.quality_gates == "mix test"
      assert member.tool_scope == ["Read", "Grep"]
      assert member.canvas_x == 100
      assert member.canvas_y == 200
    end

    test "rejects missing team_id" do
      assert {:error, _} =
               TeamMember.create(%{
                 slot: 1,
                 name: "orphan",
                 extra_instructions: "x",
                 file_scope: ".",
                 quality_gates: "mix compile"
               })
    end

    test "rejects missing slot", %{team: team} do
      assert {:error, _} =
               TeamMember.create(%{
                 team_id: team.id,
                 name: "no-slot",
                 extra_instructions: "x",
                 file_scope: ".",
                 quality_gates: "mix compile"
               })
    end

    test "rejects missing name", %{team: team} do
      assert {:error, _} =
               TeamMember.create(%{
                 team_id: team.id,
                 slot: 1,
                 extra_instructions: "x",
                 file_scope: ".",
                 quality_gates: "mix compile"
               })
    end

    test "rejects duplicate team_id + slot (unique identity)", %{team: team} do
      assert {:ok, _} = TeamMember.create(base_params(team.id, 10, "First"))
      assert {:error, _} = TeamMember.create(base_params(team.id, 10, "Second"))
    end

    test "allows same slot in different teams" do
      {:ok, team_b} = Team.create(%{name: "tm-b-#{System.unique_integer([:positive])}"})
      {:ok, team_c} = Team.create(%{name: "tm-c-#{System.unique_integer([:positive])}"})

      assert {:ok, _} = TeamMember.create(base_params(team_b.id, 99, "B member"))
      assert {:ok, _} = TeamMember.create(base_params(team_c.id, 99, "C member"))
    end
  end

  describe "for_team" do
    test "returns members for a team sorted by position then slot", %{team: team} do
      {:ok, _} = TeamMember.create(base_params(team.id, 2, "B", %{position: 1}))
      {:ok, _} = TeamMember.create(base_params(team.id, 1, "A", %{position: 0}))
      assert {:ok, members} = TeamMember.for_team(team.id)
      assert length(members) == 2
      positions = Enum.map(members, & &1.position)
      assert positions == Enum.sort(positions)
    end

    test "returns empty list for team with no members" do
      {:ok, empty_team} = Team.create(%{name: "empty-#{System.unique_integer([:positive])}"})
      assert {:ok, []} = TeamMember.for_team(empty_team.id)
    end

    test "does not return members from other teams", %{team: team} do
      {:ok, other_team} = Team.create(%{name: "other-#{System.unique_integer([:positive])}"})
      {:ok, _} = TeamMember.create(base_params(team.id, 1, "Mine"))
      {:ok, _} = TeamMember.create(base_params(other_team.id, 1, "Theirs"))

      assert {:ok, mine} = TeamMember.for_team(team.id)
      assert Enum.all?(mine, &(&1.team_id == team.id))
    end
  end

  describe "for_team_with_type" do
    test "returns members with agent_type loaded", %{team: team} do
      {:ok, at} =
        AgentType.create(%{
          name: "loaded-type-#{System.unique_integer([:positive])}",
          default_persona: "test",
          default_file_scope: ".",
          color: "#000"
        })

      {:ok, _} =
        TeamMember.create(base_params(team.id, 1, "Typed", %{agent_type_id: at.id}))

      assert {:ok, [member | _]} = TeamMember.for_team_with_type(team.id)
      assert match?(%AgentType{}, member.agent_type)
      assert member.agent_type.id == at.id
    end

    test "agent_type is nil when not set", %{team: team} do
      {:ok, _} = TeamMember.create(base_params(team.id, 1, "Untyped"))
      assert {:ok, [member | _]} = TeamMember.for_team_with_type(team.id)
      assert is_nil(member.agent_type)
    end
  end

  describe "update" do
    test "updates name", %{team: team} do
      {:ok, member} = TeamMember.create(base_params(team.id, 1, "Old"))
      assert {:ok, updated} = TeamMember.update(member, %{name: "New"})
      assert updated.name == "New"
    end

    test "updates model", %{team: team} do
      {:ok, member} = TeamMember.create(base_params(team.id, 1, "M"))
      assert {:ok, updated} = TeamMember.update(member, %{model: "haiku"})
      assert updated.model == "haiku"
    end

    test "updates canvas position", %{team: team} do
      {:ok, member} = TeamMember.create(base_params(team.id, 1, "C"))
      assert {:ok, updated} = TeamMember.update(member, %{canvas_x: 500, canvas_y: 400})
      assert updated.canvas_x == 500
      assert updated.canvas_y == 400
    end
  end

  describe "destroy" do
    test "destroys a team member", %{team: team} do
      {:ok, member} = TeamMember.create(base_params(team.id, 1, "Del"))
      assert :ok = TeamMember.destroy(member)
    end

    test "destroyed member is no longer in for_team results", %{team: team} do
      {:ok, member} = TeamMember.create(base_params(team.id, 1, "Gone"))
      :ok = TeamMember.destroy(member)
      assert {:ok, []} = TeamMember.for_team(team.id)
    end
  end
end
