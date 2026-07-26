defmodule MemoryStore.StoreCase do
  @moduledoc """
  Test case that gives each test a fresh data directory and a running store.

  `MemoryStore` is a singleton over named ETS tables, so tests cannot run
  concurrently. Each test gets its own `:data_dir`, and the process is restarted
  between tests so ETS starts empty.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import MemoryStore.StoreCase
    end
  end

  setup tags do
    dir = Path.join(System.tmp_dir!(), "memory_store_test_#{:erlang.unique_integer([:positive])}")

    put_config(:data_dir, dir)
    put_config(:flush_interval_ms, tags[:flush_interval_ms] || 60_000)

    for key <- [
          :default_block_limit,
          :recall_limit,
          :archival_ets_limit,
          :max_agents,
          :max_blocks,
          :notifier,
          :notifier_target
        ] do
      if value = tags[key], do: put_config(key, value)
    end

    on_exit(fn ->
      File.rm_rf!(dir)

      for key <- [
            :data_dir,
            :flush_interval_ms,
            :default_block_limit,
            :recall_limit,
            :archival_ets_limit,
            :max_agents,
            :max_blocks,
            :notifier,
            :notifier_target
          ] do
        Application.delete_env(:memory_store, key)
      end
    end)

    start_supervised!(MemoryStore)

    {:ok, data_dir: dir}
  end

  @doc "Set a `:memory_store` config key for the duration of the test."
  def put_config(key, value), do: Application.put_env(:memory_store, key, value)

  @doc "Stop the store, flushing on the way out, then start a fresh one."
  def restart_store do
    stop_supervised!(MemoryStore)
    start_supervised!(MemoryStore)
    :ok
  end

  @doc "Create an agent with a single block and return `{agent, block}`."
  def agent_with_block(name, attrs \\ %{label: "persona", value: "initial"}) do
    {:ok, agent} = MemoryStore.create_agent(name, [attrs])
    {:ok, core} = MemoryStore.read_core_memory(name)
    {agent, hd(core.blocks)}
  end
end
