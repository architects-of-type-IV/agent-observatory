defmodule Ichor.TestSupport.MesStubTeamLifecycle do
  @moduledoc false

  def spawn_run(run_id, team_name) do
    notify({:spawn_run, run_id, team_name})
    {:ok, "mes-#{run_id}"}
  end

  def spawn_corrective_agent(run_id, session, reason, attempt) do
    notify({:spawn_corrective_agent, run_id, session, reason, attempt})
    :ok
  end

  def kill_session(session) do
    notify({:kill_session, session})
    :ok
  end

  defp notify(message) do
    if pid = Application.get_env(:ichor, :mes_test_pid) do
      send(pid, message)
    end
  end
end
