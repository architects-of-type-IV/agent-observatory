defmodule Ichor.TestSupport.MesStubRunProcess do
  def list_all do
    Application.get_env(:ichor, :mes_test_runs, [])
  end
end
