defmodule Ichor.Fleet.AgentProcess.RegistryTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.AgentProcess.Registry

  test "builds initial registry metadata from state and backend" do
    state = %{
      role: :worker,
      team: "alpha",
      backend: %{type: :tmux, session: "alpha:lead"},
      metadata: %{}
    }

    meta = Registry.build_initial_meta("lead-1", state, %{cwd: "/tmp/app", model: "sonnet"})

    assert meta.team == "alpha"
    assert meta.tmux_target == "alpha:lead"
    assert meta.tmux_session == "alpha"
    assert meta.cwd == "/tmp/app"
    assert meta.model == "sonnet"
  end

  test "derives event-driven registry fields" do
    fields =
      Registry.fields_from_event(%{
        model_name: "gpt-5",
        cwd: "/tmp/proj",
        os_pid: 123,
        hook_event_type: :PreToolUse,
        tool_name: "Read"
      })

    assert fields.model == "gpt-5"
    assert fields.cwd == "/tmp/proj"
    assert fields.os_pid == 123
    assert fields.current_tool == "Read"
  end
end
