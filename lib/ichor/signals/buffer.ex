defmodule Ichor.Signals.Buffer do
  @moduledoc """
  Ring buffer for the Signals nervous system.
  Subscribes to all signal categories via `Ichor.Signals.subscribe/1`.
  Re-broadcasts each entry on "stream:feed" for the /signals LiveView page.
  """
  use GenServer

  alias Ichor.Signals.{Catalog, Message}

  @max_events 500
  @table :signal_buffer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Return the last N captured signals, newest first."
  @spec recent(non_neg_integer()) :: [map()]
  def recent(limit \\ 100) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_id, e} -> e.seq end, :desc)
    |> Enum.take(limit)
    |> Enum.map(&elem(&1, 1))
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

    summary =
      sig.data
      |> Map.drop([:scope_id])
      |> Enum.map_join(" ", fn {k, v} -> "#{k}=#{short_val(v)}" end)

    entry = %{
      seq: next,
      topic: "#{sig.domain}:#{sig.name}",
      shape: ":#{sig.name}",
      summary: summary,
      at: DateTime.utc_now(),
      raw: inspect(sig.data, limit: 300, printable_limit: 300) |> String.slice(0, 500)
    }

    :ets.insert(@table, {next, entry})
    maybe_evict(next)
    Phoenix.PubSub.broadcast(Ichor.PubSub, "stream:feed", {:stream_event, entry})
    {:noreply, %{state | seq: next}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp short_val(v) when is_binary(v) and byte_size(v) > 20, do: String.slice(v, 0, 16) <> ".."
  defp short_val(v) when is_binary(v), do: v
  defp short_val(v), do: inspect(v, limit: 5)

  defp maybe_evict(seq) when seq > @max_events do
    cutoff = seq - @max_events

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {id, _} -> id <= cutoff end)
    |> Enum.each(fn {id, _} -> :ets.delete(@table, id) end)
  end

  defp maybe_evict(_), do: :ok
end
