defmodule MemoryStore.Config do
  @moduledoc """
  Runtime configuration for `MemoryStore`.

  Every value has a default, so the store runs with no configuration at all.
  Override under the `:memory_store` application key:

      config :memory_store,
        data_dir: "~/.myapp/memory",
        flush_interval_ms: 10_000,
        default_block_limit: 2_000,
        recall_limit: 200,
        archival_ets_limit: 500,
        max_agents: 100,
        max_blocks: 1_000,
        notifier: MyApp.MemoryNotifier

  `MemoryStore` is a singleton — one named process backed by named ETS tables —
  so these are read from application env rather than passed per instance. Set
  `:data_dir` before starting the process; it is read once at init and on every
  disk read thereafter.
  """

  @defaults %{
    data_dir: "~/.memory_store",
    flush_interval_ms: 10_000,
    default_block_limit: 2_000,
    recall_limit: 200,
    archival_ets_limit: 500,
    max_agents: 100,
    max_blocks: 1_000,
    notifier: MemoryStore.Notifier.Noop
  }

  @doc "Root directory for persisted memory, expanded from `~`."
  @spec data_dir() :: String.t()
  def data_dir, do: Path.expand(get(:data_dir))

  @doc "Milliseconds between background flushes of dirty records to disk."
  @spec flush_interval_ms() :: pos_integer()
  def flush_interval_ms, do: get(:flush_interval_ms)

  @doc "Character cap applied to a block that does not specify its own `:limit`."
  @spec default_block_limit() :: pos_integer()
  def default_block_limit, do: get(:default_block_limit)

  @doc "How many recall entries are kept in ETS per agent. Older ones age out."
  @spec recall_limit() :: pos_integer()
  def recall_limit, do: get(:recall_limit)

  @doc """
  How many archival entries are kept in ETS per agent.

  Once an agent reaches this many, reads fall back to the on-disk JSONL file so
  search still covers everything.
  """
  @spec archival_ets_limit() :: pos_integer()
  def archival_ets_limit, do: get(:archival_ets_limit)

  @doc "Maximum number of agents."
  @spec max_agents() :: pos_integer()
  def max_agents, do: get(:max_agents)

  @doc "Maximum number of memory blocks."
  @spec max_blocks() :: pos_integer()
  def max_blocks, do: get(:max_blocks)

  @doc "Module implementing `MemoryStore.Notifier`. Defaults to a no-op."
  @spec notifier() :: module()
  def notifier, do: get(:notifier)

  defp get(key), do: Application.get_env(:memory_store, key, Map.fetch!(@defaults, key))
end
