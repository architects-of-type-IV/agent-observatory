defmodule Observatory.EventJanitor do
  @moduledoc """
  Periodically purges old events from SQLite to keep the database small.
  Runs every 6 hours and deletes events older than @retention_days.
  """
  use GenServer
  require Logger
  import Ecto.Query

  @retention_days 7
  @interval_ms :timer.hours(6)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # First purge after 30 seconds so startup is not blocked.
    Process.send_after(self(), :purge, 30_000)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:purge, state) do
    Process.send_after(self(), :purge, @interval_ms)
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days, :day)

    {count, _} =
      from(e in "events", where: e.inserted_at < ^cutoff)
      |> Observatory.Repo.delete_all()

    if count > 0 do
      Logger.info("EventJanitor: purged #{count} events older than #{@retention_days} days")
    end

    {:noreply, state}
  end
end
