defmodule Ichor.Mes.TeamCleanupTest do
  use ExUnit.Case, async: false

  alias Ichor.Mes.TeamCleanup

  setup do
    prompt_root =
      Path.join(System.tmp_dir!(), "mes-team-cleanup-#{System.unique_integer([:positive])}")

    File.mkdir_p!(prompt_root)

    Application.put_env(:ichor, :mes_prompt_root_dir, prompt_root)
    Application.put_env(:ichor, :mes_cleanup_module, Ichor.TestSupport.MesStubTeamCleanup)
    Application.put_env(:ichor, :mes_tmux_launcher_module, Ichor.TestSupport.MesStubTmuxLauncher)

    Application.put_env(
      :ichor,
      :mes_team_supervisor_module,
      Ichor.TestSupport.MesStubTeamSupervisor
    )

    Application.put_env(:ichor, :mes_run_process_module, Ichor.TestSupport.MesStubRunProcess)
    Application.put_env(:ichor, :mes_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ichor, :mes_prompt_root_dir)
      Application.delete_env(:ichor, :mes_cleanup_module)
      Application.delete_env(:ichor, :mes_tmux_launcher_module)
      Application.delete_env(:ichor, :mes_team_supervisor_module)
      Application.delete_env(:ichor, :mes_run_process_module)
      Application.delete_env(:ichor, :mes_test_pid)
      Application.delete_env(:ichor, :mes_test_team_entries)
      Application.delete_env(:ichor, :mes_test_tmux_sessions)
      Application.delete_env(:ichor, :mes_test_runs)
      File.rm_rf(prompt_root)
    end)

    {:ok, prompt_root: prompt_root}
  end

  test "computes orphaned team names and tmux sessions" do
    active = MapSet.new(["mes-run-1"])

    assert TeamCleanup.orphaned_team_names(active, [
             {"mes-run-1", %{}},
             {"mes-run-2", %{}},
             {"other", %{}}
           ]) == ["mes-run-2"]

    assert TeamCleanup.orphaned_sessions(active, ["mes-run-1", "mes-run-3", "other"]) == [
             "mes-run-3"
           ]
  end

  test "cleanup_prompt_files delegates prompt dir deletion", %{prompt_root: prompt_root} do
    prompt_dir = Path.join(prompt_root, "run-123")
    File.mkdir_p!(prompt_dir)
    File.write!(Path.join(prompt_dir, "coordinator.prompt"), "hello")

    assert :ok = TeamCleanup.cleanup_prompt_files("run-123")
    assert_receive {:cleanup_prompt_dir, ^prompt_dir}
    refute File.exists?(prompt_dir)
  end

  test "cleanup_orphaned_teams delegates generic cleanup with MES-derived active teams" do
    Application.put_env(:ichor, :mes_test_runs, [{"run-1", self()}])
    Application.put_env(:ichor, :mes_test_team_entries, [{"mes-run-1", %{}}, {"mes-run-2", %{}}])
    Application.put_env(:ichor, :mes_test_tmux_sessions, ["mes-run-1", "mes-run-3"])

    assert :ok = TeamCleanup.cleanup_orphaned_teams()
    assert_receive {:cleanup_orphaned_teams_with, active_teams, "mes-"}
    assert_receive {:cleanup_orphaned_tmux_sessions, ^active_teams, "mes-"}
    assert MapSet.equal?(active_teams, MapSet.new(["mes-run-1"]))
  end
end
