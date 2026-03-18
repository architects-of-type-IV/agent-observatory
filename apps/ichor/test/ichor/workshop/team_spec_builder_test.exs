defmodule Ichor.Workshop.TeamSpecBuilderTest do
  use ExUnit.Case, async: true

  alias Ichor.Workshop.{BlueprintState, TeamSpecBuilder}

  test "builds lifecycle team spec from workshop state" do
    state = %{
      BlueprintState.defaults()
      | ws_team_name: "Alpha Team",
        ws_strategy: "one_for_one",
        ws_cwd: "/tmp/project",
        ws_agents: [
          %{
            id: 1,
            name: "Lead",
            capability: "lead",
            model: "opus",
            permission: "default",
            persona: "Owns coordination.",
            file_scope: "lib/",
            quality_gates: "mix test"
          },
          %{
            id: 2,
            name: "Builder",
            capability: "builder",
            model: "sonnet",
            permission: "default",
            persona: "",
            file_scope: "",
            quality_gates: "mix compile"
          }
        ],
        ws_spawn_links: [%{from: 1, to: 2}],
        ws_comm_rules: [%{from: 1, to: 2, policy: "allow", via: nil}],
        ws_blueprint_id: "bp-1"
    }

    spec = TeamSpecBuilder.build_from_state(state)

    assert spec.team_name == "Alpha Team"
    assert spec.session == "workshop-alpha-team"
    assert spec.cwd == "/tmp/project"
    assert spec.prompt_dir =~ "alpha-team"
    assert spec.metadata.blueprint_id == "bp-1"
    assert length(spec.agents) == 2

    [lead, builder] = spec.agents
    assert lead.name == "Lead"
    assert lead.window_name == "1-lead"
    assert lead.agent_id == "workshop-alpha-team-1-lead"
    assert lead.prompt =~ "You are Lead"
    assert lead.prompt =~ "Spawn responsibilities"
    assert lead.prompt =~ "Communication rules"
    assert builder.name == "Builder"
  end
end
