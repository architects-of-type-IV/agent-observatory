defmodule Ichor.Archon.SignalManager do
  @moduledoc """
  Signal-fed managerial state for Archon.

  Archon subscribes to the system nervous system and projects a compact
  view of current activity plus a short attention queue.
  """

  use GenServer

  alias Ichor.Archon.SignalManager.Reactions
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return a compact map of signal counts and latest activity."
  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc "Return the current attention queue (signals requiring intervention)."
  @spec attention() :: [map()]
  def attention do
    GenServer.call(__MODULE__, :attention)
  end

  @impl true
  def init(_opts) do
    Enum.each(Signals.categories(), &Signals.subscribe/1)
    {:ok, Reactions.new_state()}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_map(state), state}
  end

  @impl true
  def handle_call(:attention, _from, state) do
    {:reply, state.attention, state}
  end

  @impl true
  def handle_info(%Message{} = message, state) do
    {:noreply, Reactions.ingest(message, state)}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp snapshot_map(state) do
    %{
      "signals_seen" => state.signal_count,
      "attention_count" => length(state.attention),
      "counts_by_category" => stringify_map(state.counts_by_category),
      "latest_by_category" => stringify_map(state.latest_by_category)
    }
  end

  defp stringify_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
