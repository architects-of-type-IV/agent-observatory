defmodule CronScheduler.Store do
  @moduledoc """
  Behaviour for the durable record of scheduled jobs.

  The store is the source of truth for *what* is scheduled; the queue only knows
  *when* to wake something up. That split is what makes recovery possible — if
  the queue loses its timers, `CronScheduler.recover_jobs/0` rebuilds them from
  the store.

  The original implementation was an Ash resource over PostgreSQL. Anything with
  these seven operations works: Ecto, Mnesia, DETS, or the bundled
  `CronScheduler.Store.ETS` for development.

  Configure with:

      config :cron_scheduler, store: MyApp.JobStore

  ## Durability

  Whatever backs this decides whether jobs survive a restart. `Store.ETS` does
  not; use it for tests and development, not for work that must not be lost.
  """

  alias CronScheduler.Job

  @doc "Persist a new job and return it, with any store-assigned id filled in."
  @callback insert(Job.t()) :: {:ok, Job.t()} | {:error, term()}

  @doc "Fetch a job by id."
  @callback get(id :: String.t()) :: {:ok, Job.t()} | {:error, :not_found | term()}

  @doc "Every job for one agent."
  @callback for_agent(agent_id :: String.t()) :: {:ok, [Job.t()]} | {:error, term()}

  @doc "Every scheduled job, soonest first."
  @callback all_scheduled() :: {:ok, [Job.t()]} | {:error, term()}

  @doc "Jobs whose `next_fire_at` is at or before `now`, soonest first."
  @callback due(now :: DateTime.t()) :: {:ok, [Job.t()]} | {:error, term()}

  @doc "Move a job's next fire time forward."
  @callback reschedule(job :: Job.t(), next_fire_at :: DateTime.t()) ::
              {:ok, Job.t()} | {:error, term()}

  @doc "Remove a finished job."
  @callback complete(job :: Job.t()) :: :ok | {:error, term()}
end
