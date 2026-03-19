defmodule Ichor.TestSupport.ArchonStubMemoriesClient do
  @moduledoc false

  def search(query, opts \\ []) do
    if pid = Application.get_env(:ichor, :archon_test_pid) do
      send(pid, {:archon_memory_search, query, opts})
    end

    scope = Keyword.get(opts, :scope)
    responses = Application.get_env(:ichor, :archon_memories_responses, %{})
    Map.get(responses, scope, {:ok, []})
  end
end
