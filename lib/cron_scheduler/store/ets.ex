defmodule CronScheduler.Store.ETS do
  @moduledoc """
  In-memory `CronScheduler.Store`, backed by a single ETS table.

  A working reference implementation and a reasonable default for development
  and tests. **Not durable** — the table dies with this process, so scheduled
  jobs do not survive a restart. Back the store with a database for anything
  that must not be lost.

  Add it to your supervision tree:

      children = [CronScheduler.Store.ETS]

      config :cron_scheduler, store: CronScheduler.Store.ETS
  """

  use GenServer

  @behaviour CronScheduler.Store

  alias CronScheduler.Job

  @table :cron_scheduler_jobs

  @doc "Start the table owner."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Delete every job. Test helper."
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl GenServer
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl CronScheduler.Store
  def insert(%Job{} = job) do
    :ets.insert(@table, {job.id, job})
    {:ok, job}
  end

  @impl CronScheduler.Store
  def get(id) do
    case :ets.lookup(@table, id) do
      [{^id, job}] -> {:ok, job}
      [] -> {:error, :not_found}
    end
  end

  @impl CronScheduler.Store
  def for_agent(agent_id) do
    {:ok, all() |> Enum.filter(&(&1.agent_id == agent_id))}
  end

  @impl CronScheduler.Store
  def all_scheduled, do: {:ok, all()}

  @impl CronScheduler.Store
  def due(%DateTime{} = now) do
    {:ok, all() |> Enum.filter(&(DateTime.compare(&1.next_fire_at, now) != :gt))}
  end

  @impl CronScheduler.Store
  def reschedule(%Job{} = job, %DateTime{} = next_fire_at) do
    updated = %{job | next_fire_at: next_fire_at}
    :ets.insert(@table, {job.id, updated})
    {:ok, updated}
  end

  @impl CronScheduler.Store
  def complete(%Job{} = job) do
    :ets.delete(@table, job.id)
    :ok
  end

  defp all do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, job} -> job end)
    |> Enum.sort_by(& &1.next_fire_at, DateTime)
  end
end
