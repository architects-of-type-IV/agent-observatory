defmodule Ichor.TestSupport.ToolsStubOperator do
  def send(to, content) do
    if pid = Application.get_env(:ichor, :tools_test_pid) do
      Kernel.send(pid, {:tools_operator_send, to, content})
    end

    {:ok, Application.get_env(:ichor, :tools_operator_delivered, 1)}
  end
end
