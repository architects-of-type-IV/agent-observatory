defmodule Ichor.TestSupport.ToolsStubRouter do
  def broadcast(channel, payload) do
    if pid = Application.get_env(:ichor, :tools_test_pid) do
      Kernel.send(pid, {:tools_router_broadcast, channel, payload})
    end

    Application.get_env(:ichor, :tools_router_result, {:ok, 1})
  end
end
