defmodule Ichor.TestSupport.MesStubTeamSupervisor do
  def list_all do
    Application.get_env(:ichor, :mes_test_team_entries, [])
  end
end
