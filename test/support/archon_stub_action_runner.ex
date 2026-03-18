defmodule Ichor.TestSupport.ArchonStubActionRunner do
  def run(type, resource, action, params) do
    if pid = Application.get_env(:ichor, :archon_test_pid) do
      send(pid, {:archon_action, type, resource, action, params})
    end

    result = Application.get_env(:ichor, :archon_action_runner_result, {:ok, %{}})

    case result do
      {:ok, data} -> {:ok, %{type: type, data: data}}
      {:error, reason} -> {:error, reason}
    end
  end
end
