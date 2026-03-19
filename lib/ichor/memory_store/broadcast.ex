defmodule Ichor.MemoryStore.Broadcast do
  @moduledoc """
  Signal emission for memory store changes.
  """

  @doc "Emit a block_changed signal."
  @spec block_changed(String.t(), String.t()) :: :ok
  def block_changed(block_id, label) do
    Ichor.Signals.emit(:block_changed, %{block_id: block_id, label: label})
  end

  @doc "Emit a scoped memory_changed signal for a specific agent."
  @spec agent_changed(String.t(), atom()) :: :ok
  def agent_changed(agent_name, event) do
    Ichor.Signals.emit(:memory_changed, agent_name, %{agent_name: agent_name, event: event})
  end
end
