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

  @doc "ETS table name for memory blocks."
  @spec blocks_table() :: atom()
  def blocks_table, do: @blocks_table

  @doc "ETS table name for agent records."
  @spec agents_table() :: atom()
  def agents_table, do: @agents_table

  @doc "ETS table name for recall entries."
  @spec recall_table() :: atom()
  def recall_table, do: @recall_table

  @doc "ETS table name for archival entries."
  @spec archival_table() :: atom()
  def archival_table, do: @archival_table

  @doc "Default character limit for a memory block."
  @spec default_block_limit() :: pos_integer()
  def default_block_limit, do: @default_block_limit

  @doc "Maximum number of recall entries kept in ETS per agent."
  @spec recall_limit() :: pos_integer()
  def recall_limit, do: @recall_limit

  @doc "Maximum number of archival entries kept in ETS per agent."
  @spec archival_ets_limit() :: pos_integer()
  def archival_ets_limit, do: @archival_ets_limit

  @doc "Maximum number of agent records."
  @spec max_agents() :: pos_integer()
  def max_agents, do: @max_agents

  @doc "Maximum number of memory blocks."
  @spec max_blocks() :: pos_integer()
  def max_blocks, do: @max_blocks

  @doc "Root directory for persisted memory data."
  @spec data_dir() :: String.t()
  def data_dir, do: Path.expand("~/.ichor/memory")
end
