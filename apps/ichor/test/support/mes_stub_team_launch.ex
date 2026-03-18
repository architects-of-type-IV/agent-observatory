defmodule Ichor.TestSupport.MesStubTeamLaunch do
  def launch(spec) do
    notify({:launch, spec})
    {:ok, spec.session}
  end

  def launch_into_existing_session(spec, session) do
    notify({:launch_into_existing_session, spec, session})
    :ok
  end

  defp notify(message) do
    if pid = Application.get_env(:ichor, :mes_test_pid) do
      send(pid, message)
    end
  end
end
