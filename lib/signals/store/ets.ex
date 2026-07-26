defmodule Signals.Store.ETS do
  @moduledoc """
  In-memory `Signals.Store`, backed by one ETS table.

  A working default for development and tests. **Not durable** — the table dies
  with this process, so accumulators restart empty and any partial conclusion is
  lost. Back it with a database anywhere a half-accumulated signal matters,
  which is most places a watchdog is worth having.

      children = [Signals.Store.ETS]
      config :signals, store: Signals.Store.ETS
  """

  use GenServer

  @behaviour Signals.Store

  @table :signals_store

  @doc "Start the table owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Drop every stored accumulator. Test helper."
  @spec clear() :: :ok
  def clear do
    if :ets.whereis(@table) != :undefined, do: :ets.delete_all_objects(@table)
    :ok
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl Signals.Store
  def put(ref, state, position) do
    :ets.insert(@table, {ref, %{state: state, position: position}})
    :ok
  end

  @impl Signals.Store
  def fetch(ref) do
    case :ets.lookup(@table, ref) do
      [{^ref, record}] -> {:ok, record}
      [] -> {:ok, :empty}
    end
  end

  @impl Signals.Store
  def delete(ref) do
    :ets.delete(@table, ref)
    :ok
  end
end

defmodule Signals.Store.Null do
  @moduledoc """
  `Signals.Store` that remembers nothing.

  Every accumulator starts fresh and no position is tracked, so replays are
  re-folded. Use only where losing partial accumulation is genuinely fine.
  """

  @behaviour Signals.Store

  @impl true
  def put(_ref, _state, _position), do: :ok

  @impl true
  def fetch(_ref), do: {:ok, :empty}

  @impl true
  def delete(_ref), do: :ok
end
