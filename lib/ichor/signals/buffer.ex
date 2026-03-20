defmodule Ichor.Signals.Buffer do
  @moduledoc """
  Ring buffer for the Signals nervous system.
  Subscribes to all signal categories via `Ichor.Signals.subscribe/1`.
  Re-broadcasts each raw signal on "signals:feed" for the /signals LiveView page.
  """
  use GenServer

  alias Ichor.Signals.Catalog
  alias Ichor.Signals.Message

  @max_events 200
  @table :signal_buffer

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return the last N captured signals as `{seq, %Message{}}` tuples, newest first."
  @spec recent(non_neg_integer()) :: [{non_neg_integer(), Message.t()}]
  def recent(limit \\ 100) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(&elem(&1, 0), :desc)
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
    :ets.insert(@table, {next, sig})
    maybe_evict(next)
    Phoenix.PubSub.broadcast(Ichor.PubSub, "signals:feed", {:signal, next, sig})
    {:noreply, %{state | seq: next}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_evict(seq) when seq > @max_events do
    cutoff = seq - @max_events
    :ets.select_delete(@table, [{{:"$1", :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

  defp maybe_evict(_), do: :ok
end
