# cron_scheduler

One-off and recurring job scheduling over a pluggable store and queue.

Extracted from the ICHOR IV agent observatory, where this was an Ash resource on
PostgreSQL plus an Oban worker. Neither of those is the interesting part — the
interesting part is the split between them, and what happens at the seam. That
is what this library is.

No dependencies.

## The two halves

**The store** (`CronScheduler.Store`) is the source of truth for *what* is
scheduled. **The queue** (`CronScheduler.Queue`) only knows *when* to wake
something up.

That split is what makes recovery possible. The queue is allowed to be
forgetful: lose every timer it holds and the schedule is still intact, because
it lives in the store. On boot, `recover_jobs/0` walks the store and re-enqueues
everything.

Both are behaviours, because neither is this library's business. The original
used PostgreSQL and Oban; the bundled `Store.ETS` and `Queue.Timer` are working
implementations you can develop against.

## Ordering at the seam

Two orderings, chosen deliberately in opposite directions:

**Scheduling writes the store first, then the queue.** If the queue rejects the
job, the store record is rolled back — so a job is never left scheduled with
nothing due to wake it.

**Firing updates the store first, then runs the handler.** One-time jobs are
deleted and recurring ones moved forward *before* the handler is called, so a
crash in the handler cannot leave a job re-firing in a loop. The trade is that
the handler's own work is lost on a crash. If that work matters, have the
handler enqueue something durable rather than doing it inline.

## Install

```elixir
def deps do
  [{:cron_scheduler, path: "../cron_scheduler"}]
end
```

Requires Elixir 1.18+ for the built-in `JSON` module.

```elixir
children = [
  CronScheduler.Store.ETS,
  CronScheduler.Queue.Timer
]

config :cron_scheduler,
  store: CronScheduler.Store.ETS,
  queue: CronScheduler.Queue.Timer,
  handler: MyApp.JobHandler
```

## Use

```elixir
{:ok, job} = CronScheduler.schedule_once("agent-1", 60_000, %{action: "health_check"})
{:ok, job} = CronScheduler.schedule_recurring("agent-1", 300_000, %{action: "poll"})

CronScheduler.list_jobs("agent-1")   #=> [%CronScheduler.Job{}]
CronScheduler.list_all_jobs()        #=> soonest first
CronScheduler.due_jobs()             #=> already due as of now
CronScheduler.cancel(job.id)         #=> :ok, whether or not it existed

CronScheduler.recover_jobs()         #=> call on boot
```

Payloads may be any JSON-encodable term; strings pass through untouched. The
store only ever sees a string, so it never has to understand what a job carries.

## The handler

```elixir
defmodule MyApp.JobHandler do
  @behaviour CronScheduler.Handler

  @impl true
  def handle_fire(agent_id, payload, _job) do
    Phoenix.PubSub.broadcast(MyApp.PubSub, "jobs", {:fired, agent_id, JSON.decode!(payload)})
  end
end
```

## Writing adapters

### Store

Seven callbacks: `insert/1`, `get/1`, `for_agent/1`, `all_scheduled/0`,
`due/1`, `reschedule/2`, `complete/1`. Anything works — Ecto, Mnesia, DETS.
Whatever backs it decides whether jobs survive a restart.

### Queue

One callback, `enqueue/2`, whose only obligation is to eventually call
`CronScheduler.fire/1` with the job's id.

`enqueue/2` receives a `:unique_period` in seconds. An implementation that can
deduplicate should drop a repeat enqueue of the same job id inside that window
and still return `:ok` — recovery and normal scheduling can race, and a job
firing twice is worse than an enqueue quietly collapsing. `Queue.Timer` does
this; an Oban adapter gets it from `unique: [period: ..., keys: [:job_id]]`.

An Oban adapter is about fifteen lines:

```elixir
defmodule MyApp.ObanQueue do
  @behaviour CronScheduler.Queue

  @impl true
  def enqueue(job, opts) do
    %{"job_id" => job.id}
    |> MyApp.FireWorker.new(
      schedule_in: Keyword.get(opts, :schedule_in, 0),
      unique: [period: Keyword.get(opts, :unique_period, 120), keys: [:job_id]]
    )
    |> Oban.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
```

The worker's `perform/1` calls `CronScheduler.fire(job_id)`.

## Bundled adapters

| Module | Durable? | For |
|---|---|---|
| `CronScheduler.Store.ETS` | No | Development and tests |
| `CronScheduler.Queue.Timer` | No | Single node that tolerates losing timers on restart |
| `CronScheduler.Handler.Noop` | — | Testing the schedule itself |
| `CronScheduler.Handler.ProcessMessage` | — | Sends `{:cron_scheduler, :fired, ...}` to a pid |

`Queue.Timer` is more usable than it sounds: it deduplicates properly, fires in
a task so a slow handler cannot stall other jobs, and pairs with `recover_jobs/0`
to rebuild its timers after a restart. What it cannot do is survive a node going
away mid-delay.

## Configuration

```elixir
config :cron_scheduler,
  store: CronScheduler.Store.ETS,          # required
  queue: CronScheduler.Queue.Timer,        # required
  handler: CronScheduler.Handler.Noop,     # optional
  default_interval_ms: 60_000              # recurring jobs with no interval of their own
```

A missing `:store` or `:queue` raises an `ArgumentError` naming the key and the
bundled default, rather than failing somewhere further down.

## Tests

```
mix test
```

67 tests covering schedule arithmetic, the rollback and recovery paths, one-time
vs recurring firing, both bundled adapters, and end-to-end scheduling through a
real timer.

## Changes from the original

- Namespace `Ichor.Infrastructure.CronScheduler` → `CronScheduler`.
- The Ash `CronJob` resource became the `CronScheduler.Store` behaviour plus a
  plain `CronScheduler.Job` struct.
- Oban became the `CronScheduler.Queue` behaviour; the `ScheduledJob` worker's
  logic moved into `CronScheduler.fire/1`, so a queue adapter is a one-liner.
- The signal emitted on fire became the `CronScheduler.Handler` behaviour.
- Jason replaced with the built-in `JSON` module.

Added and fixed along the way:

- **A failed enqueue used to leave an orphaned record.** The original inserted
  into the database, and on an Oban failure called `CronJob.complete(job)` — but
  only in `schedule_once`, and the rollback was easy to miss. It is now the
  single path out of `enqueue_or_rollback/2`, and tested.
- **Sub-second delays fired immediately.** `div(delay_ms, 1000)` rounded a 900 ms
  delay down to `schedule_in: 0`. `Schedule.to_seconds/1` rounds up instead.
- **The recurring interval was hardcoded to 60 s** in the worker. It now lives
  on the job, so `schedule_recurring/3` can take any interval, with a
  configurable fallback.
- `schedule_recurring/3`, `cancel/1`, and `due_jobs/1` are new — the store
  supported them, but nothing exposed them.
