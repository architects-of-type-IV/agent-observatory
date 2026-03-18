defmodule Ichor.Mes.TeamSpawnerTest do
  use ExUnit.Case, async: false

  alias Ichor.Mes.TeamSpawner

  setup do
    prompt_root =
      Path.join(System.tmp_dir!(), "mes-team-spawner-#{System.unique_integer([:positive])}")

    Application.put_env(:ichor, :mes_prompt_root_dir, prompt_root)
    Application.put_env(:ichor, :mes_team_launch_module, Ichor.TestSupport.MesStubTeamLaunch)
    Application.put_env(:ichor, :mes_team_cleanup_module, Ichor.TestSupport.MesStubTeamCleanup)
    Application.put_env(:ichor, :mes_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ichor, :mes_prompt_root_dir)
      Application.delete_env(:ichor, :mes_team_launch_module)
      Application.delete_env(:ichor, :mes_team_cleanup_module)
      Application.delete_env(:ichor, :mes_test_pid)
    end)

    :ok
  end

  test "spawn_run delegates through the compatibility facade" do
    assert {:ok, "mes-run-123"} = TeamSpawner.spawn_run("run-123", "mes-run-123")
    assert_receive {:launch, %{session: "mes-run-123", team_name: "mes-run-123"}}
  end

  test "spawn_corrective_agent delegates through the compatibility facade" do
    assert :ok = TeamSpawner.spawn_corrective_agent("run-123", "mes-run-123", "bad brief", 2)
    assert_receive {:launch_into_existing_session, %{session: "mes-run-123"}, "mes-run-123"}
  end

  test "cleanup facade delegates to MES cleanup coordinator" do
    assert :ok = TeamSpawner.cleanup_orphaned_teams()
    assert_receive :cleanup_orphaned_teams
  end
end
