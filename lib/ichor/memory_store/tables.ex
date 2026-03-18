defmodule Ichor.MemoryStore.Tables do
  @moduledoc """
  Shared table names and limits for the memory store.
  """

  @blocks_table :letta_blocks
  @agents_table :letta_agents
  @recall_table :letta_recall
  @archival_table :letta_archival
  @default_block_limit 2000
  @recall_limit 200
  @archival_ets_limit 500
  @max_agents 100
  @max_blocks 1000

  def blocks_table, do: @blocks_table
  def agents_table, do: @agents_table
  def recall_table, do: @recall_table
  def archival_table, do: @archival_table
  def default_block_limit, do: @default_block_limit
  def recall_limit, do: @recall_limit
  def archival_ets_limit, do: @archival_ets_limit
  def max_agents, do: @max_agents
  def max_blocks, do: @max_blocks
  def data_dir, do: Path.expand("~/.ichor/memory")
end
