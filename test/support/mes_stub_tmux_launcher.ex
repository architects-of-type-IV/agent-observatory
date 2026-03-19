defmodule Ichor.TestSupport.MesStubTmuxLauncher do
  def list_sessions do
    Application.get_env(:ichor, :mes_test_tmux_sessions, [])
  end
end
