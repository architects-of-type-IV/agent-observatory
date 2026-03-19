defmodule Ichor.TestSupport.ArchonStubTurnRunner do
  def run(chain, messages, user_input) do
    if pid = Application.get_env(:ichor, :archon_test_pid) do
      send(pid, {:archon_turn_runner, chain, messages, user_input})
    end

    {:ok, "stubbed response", messages ++ [user_input]}
  end
end
