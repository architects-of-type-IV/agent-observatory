defmodule CronScheduler.Queue do
  @moduledoc """
  Behaviour for the delayed-dispatch side of scheduling.

  The queue's one job is to call `CronScheduler.fire/1` with a job id after a
  delay. It does not need to know what the job means, and it does not need to be
  durable — the store is the source of truth, and
  `CronScheduler.recover_jobs/0` rebuilds timers after a restart.

  The original implementation was Oban. `CronScheduler.Queue.Timer` ships as an
  in-process implementation over `Process.send_after/3`.

  Configure with:

      config :cron_scheduler, queue: MyApp.ObanQueue

  ## Deduplication

  `enqueue/2` receives a `:unique_period` option, in seconds. An implementation
  that can deduplicate should drop a second enqueue of the same job id inside
  that window and still return `:ok` — recovery and normal scheduling can race,
  and a job firing twice is worse than an enqueue quietly collapsing.
  """

  alias CronScheduler.Job

  @typedoc """
  Enqueue options.

    * `:schedule_in` — seconds to wait before firing; `0` means as soon as possible
    * `:unique_period` — seconds within which a repeat enqueue of this job id
      should be treated as a duplicate
  """
  @type opts :: [schedule_in: non_neg_integer(), unique_period: non_neg_integer()]

  @doc """
  Arrange for `CronScheduler.fire/1` to be called with this job's id.

  Returning `{:error, reason}` makes `CronScheduler.schedule_once/3` roll back
  the store record, so a job never sits scheduled with nothing due to wake it.
  """
  @callback enqueue(job :: Job.t(), opts :: opts()) :: :ok | {:error, term()}
end
