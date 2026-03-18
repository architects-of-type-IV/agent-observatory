defmodule Ichor.MemoryStore.Broadcast do
  @moduledoc """
  Signal emission for memory store changes.
  """

  def block_changed(block_id, label) do
    Ichor.Signals.emit(:block_changed, %{block_id: block_id, label: label})
  end

  def agent_changed(agent_name, event) do
    Ichor.Signals.emit(:memory_changed, agent_name, %{agent_name: agent_name, event: event})
  end
end
