defmodule Ichor.Projector.SignalBuffer do
  @moduledoc """
  Ring buffer for the event stream.
  Subscribes to all events via `Ichor.Events.subscribe_all/0`.
  Re-broadcasts each event on "signals:feed" for the /signals LiveView page.
  """
  use GenServer

  alias Ichor.Events.Event

  @max_events 200
  @table :signal_buffer

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return the last N captured events as `{seq, %Event{}}` tuples, newest first."
  @spec recent(non_neg_integer()) :: [{non_neg_integer(), Event.t()}]
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
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set])
      _ -> :ok
    end

    Ichor.Events.subscribe_all()
    {:ok, %{seq: 0}}
  end

  @impl true
  def handle_info(%Event{} = event, %{seq: seq} = state) do
    next = seq + 1
    :ets.insert(@table, {next, event})
    maybe_evict(next)
    Phoenix.PubSub.broadcast(Ichor.PubSub, "signals:feed", {:signal, next, event})
    {:noreply, %{state | seq: next}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp maybe_evict(seq) when seq > @max_events do
    cutoff = seq - @max_events
    :ets.select_delete(@table, [{{:"$1", :_}, [{:"=<", :"$1", cutoff}], [true]}])
  end

  defp maybe_evict(_), do: :ok
end
