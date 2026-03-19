defmodule Ichor.Signals.Buffer do
  @moduledoc """
  Ring buffer for the Signals nervous system.
  Subscribes to all signal categories via `Ichor.Signals.subscribe/1`.
  Re-broadcasts each entry on "stream:feed" for the /signals LiveView page.
  """
  use GenServer

  alias Ichor.Signals.{Catalog, EntryFormatter, Message}

  @max_events 200
  @table :signal_buffer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return the last N captured signals, newest first."
  @spec recent(non_neg_integer()) :: [map()]
  def recent(limit \\ 100) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Stream.map(&elem(&1, 1))
    |> Enum.take(limit)
  rescue
    ArgumentError -> []
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    Enum.each(Catalog.categories(), &Ichor.Signals.subscribe/1)
    {:ok, %{seq: 0}}
  end

  @impl true
  def handle_info(%Message{} = sig, %{seq: seq} = state) do
    next = seq + 1
    entry = EntryFormatter.format(sig, next)
    :ets.insert(@table, {next, entry})
    maybe_evict(next)
    Phoenix.PubSub.broadcast(Ichor.PubSub, "stream:feed", {:stream_event, entry})
    {:noreply, %{state | seq: next}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_evict(seq) when seq > @max_events do
    cutoff = seq - @max_events
    :ets.select_delete(@table, [{{:"$1", :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

  defp maybe_evict(_), do: :ok
end
