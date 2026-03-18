defmodule Ichor.Mes.RunProcessTest do
  use ExUnit.Case, async: false

  alias Ichor.Mes.RunProcess
  alias Ichor.Signals.Message

  setup do
    Application.put_env(
      :ichor,
      :mes_team_lifecycle_module,
      Ichor.TestSupport.MesStubTeamLifecycle
    )

    Application.put_env(:ichor, :mes_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ichor, :mes_team_lifecycle_module)
      Application.delete_env(:ichor, :mes_test_pid)
    end)

    :ok
  end

  test "spawn_team continue delegates to the lifecycle boundary" do
    state = %RunProcess{
      run_id: "run-123",
      team_name: "mes-run-123",
      session: "mes-run-123",
      deadline_passed: false
    }

    assert {:noreply, %RunProcess{session: "mes-run-123"}} =
             RunProcess.handle_continue(:spawn_team, state)

    assert_receive {:spawn_run, "run-123", "mes-run-123"}
  end

  test "quality gate failure triggers a corrective agent launch" do
    state = %RunProcess{
      run_id: "run-123",
      team_name: "mes-run-123",
      session: "mes-run-123",
      deadline_passed: false,
      gate_failures: 0
    }

    assert {:noreply, %RunProcess{gate_failures: 1}} =
             RunProcess.handle_info(
               Message.build(:mes_quality_gate_failed, :mes, %{
                 run_id: "run-123",
                 reason: "missing field"
               }),
               state
             )

    assert_receive {:spawn_corrective_agent, "run-123", "mes-run-123", "missing field", 1}
  end

  test "project creation kills the team session through the lifecycle boundary" do
    state = %RunProcess{
      run_id: "run-123",
      team_name: "mes-run-123",
      session: "mes-run-123",
      deadline_passed: false
    }

    assert {:stop, :normal, ^state} =
             RunProcess.handle_info(
               Message.build(:mes_project_created, :mes, %{run_id: "run-123"}),
               state
             )

    assert_receive {:kill_session, "mes-run-123"}
  end
end
