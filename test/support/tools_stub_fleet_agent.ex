defmodule Ichor.TestSupport.ToolsStubFleetAgent do
  def send_message(to, content, opts) do
    if pid = Application.get_env(:ichor, :tools_test_pid) do
      Kernel.send(pid, {:tools_fleet_agent_send, to, content, opts})
    end

    Application.get_env(:ichor, :tools_fleet_agent_result, {:ok, %{}})
  end
end
