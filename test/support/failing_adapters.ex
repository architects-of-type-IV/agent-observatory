defmodule CronScheduler.Test.FailingQueue do
  @moduledoc "Queue that always refuses, to exercise the rollback path."

  @behaviour CronScheduler.Queue

  @impl true
  def enqueue(_job, _opts), do: {:error, :queue_down}
end

defmodule CronScheduler.Test.FailingStore do
  @moduledoc "Store that always refuses inserts, to exercise the insert-failure path."

  @behaviour CronScheduler.Store

  @impl true
  def insert(_job), do: {:error, :store_down}

  @impl true
  def get(_id), do: {:error, :store_down}

  @impl true
  def for_agent(_agent_id), do: {:error, :store_down}

  @impl true
  def all_scheduled, do: {:error, :store_down}

  @impl true
  def due(_now), do: {:error, :store_down}

  @impl true
  def reschedule(_job, _at), do: {:error, :store_down}

  @impl true
  def complete(_job), do: {:error, :store_down}
end

defmodule CronScheduler.Test.RecordingQueue do
  @moduledoc """
  Queue that records enqueues instead of scheduling them.

  Lets tests assert on what would have been enqueued, and fire jobs by hand,
  without waiting on real timers.
  """

  @behaviour CronScheduler.Queue

  @table :cron_scheduler_test_enqueues

  def setup do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :duplicate_bag])
    end

    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def enqueue(job, opts) do
    :ets.insert(@table, {:enqueue, job, opts})
    :ok
  end

  @doc "Every recorded enqueue as `{job, opts}`, oldest first."
  def enqueues do
    @table
    |> :ets.lookup(:enqueue)
    |> Enum.map(fn {:enqueue, job, opts} -> {job, opts} end)
  end

  @doc "Recorded enqueues for one job id."
  def enqueues_for(job_id), do: Enum.filter(enqueues(), fn {job, _} -> job.id == job_id end)
end
