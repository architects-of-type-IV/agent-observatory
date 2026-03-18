defmodule Ichor.Mes.TeamSpecBuilderTest do
  use ExUnit.Case, async: true

  alias Ichor.Mes.TeamSpecBuilder

  setup do
    prompt_root =
      Path.join(System.tmp_dir!(), "mes-team-spec-builder-#{System.unique_integer([:positive])}")

    Application.put_env(:ichor, :mes_prompt_root_dir, prompt_root)
    on_exit(fn -> Application.delete_env(:ichor, :mes_prompt_root_dir) end)
    :ok
  end

  test "build_team_spec creates the five-agent MES roster" do
    spec = TeamSpecBuilder.build_team_spec("run-123", "mes-run-123")

    assert spec.session == "mes-run-123"
    assert spec.team_name == "mes-run-123"
    assert spec.prompt_dir == Path.join(TeamSpecBuilder.prompt_root_dir(), "run-123")
    assert spec.metadata == %{run_id: "run-123"}

    assert Enum.map(spec.agents, & &1.name) == [
             "coordinator",
             "lead",
             "planner",
             "researcher-1",
             "researcher-2"
           ]

    assert Enum.map(spec.agents, & &1.window_name) == [
             "coordinator",
             "lead",
             "planner",
             "researcher-1",
             "researcher-2"
           ]

    assert Enum.map(spec.agents, & &1.agent_id) == [
             "mes-run-123-coordinator",
             "mes-run-123-lead",
             "mes-run-123-planner",
             "mes-run-123-researcher-1",
             "mes-run-123-researcher-2"
           ]
  end

  test "build_corrective_team_spec creates a single corrective agent" do
    spec = TeamSpecBuilder.build_corrective_team_spec("run-123", "mes-run-123", "retry", 2)

    assert spec.session == "mes-run-123"
    assert spec.team_name == "mes-run-123"
    assert spec.prompt_dir == Path.join(TeamSpecBuilder.prompt_root_dir(), "run-123")

    assert [
             %{
               name: "corrective-2",
               window_name: "corrective-2",
               agent_id: "mes-run-123-corrective-2"
             }
           ] = spec.agents
  end
end
