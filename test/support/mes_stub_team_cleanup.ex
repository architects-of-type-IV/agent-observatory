defmodule Ichor.TestSupport.MesStubTeamCleanup do
  @moduledoc false

  def kill_session(session) do
    notify({:kill_session, session})
    :ok
  end

  def cleanup_old_runs do
    notify(:cleanup_old_runs)
    :ok
  end

  def cleanup_orphaned_teams do
    notify(:cleanup_orphaned_teams)
    :ok
  end

  def cleanup_prompt_dir(dir) do
    notify({:cleanup_prompt_dir, dir})
    File.rm_rf!(dir)
    :ok
  end

  def cleanup_orphaned_teams(active_teams, prefix) do
    notify({:cleanup_orphaned_teams_with, active_teams, prefix})
    :ok
  end

  def cleanup_orphaned_tmux_sessions(active_teams, prefix) do
    notify({:cleanup_orphaned_tmux_sessions, active_teams, prefix})
    :ok
  end

  defp notify(message) do
    if pid = Application.get_env(:ichor, :mes_test_pid) do
      send(pid, message)
    end
  end
end
