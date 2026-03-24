# Implementation Brief: Pipeline Health Monitor
**Brief ID:** 69f1f570
**Plugin:** `Ichor.Plugins.PipelineHealthMonitor`
**Version:** 0.1.0

---

## Signal Catalog Additions

Add to `lib/ichor/signals/catalog.ex` under a new `@plugin_defs` map, merged into `@signals`:

```elixir
@plugin_defs %{
  health_score_updated: %{
    category: :pipeline,
    keys: [:run_id, :score, :components],
    doc: "Pipeline health score updated; score is 0.0-1.0 float"
  },
  pipeline_degraded: %{
    category: :pipeline,
    keys: [:run_id, :reason, :score],
    doc: "Pipeline health dropped below degraded threshold"
  },
  run_health_finalized: %{
    category: :pipeline,
    keys: [:run_id, :final_score, :summary],
    doc: "Final health score emitted on run_complete"
  }
}
```

**NOTE:** The brief's proposed signals (`run_started`, `agent_heartbeat`, `agent_stalled`, `worker_absent`, `entropy_spike`) do not exist in the catalog. Use actual existing signals:

| Brief term | Actual catalog signal | Category |
|---|---|---|
| run_started | `mes_run_started` | `:mes` |
| run_complete | `run_complete` | `:fleet` |
| entropy_spike | `entropy_alert` | `:gateway` |
| agent_stalled | `nudge_escalated` + `agent_evicted` | `:agent` / `:fleet` |
| worker_absent | `mes_agent_stopped` | `:mes` |
| agent_heartbeat | `heartbeat` (system) — per-agent heartbeat does not exist | n/a |

There is no per-agent heartbeat signal. The health monitor will track **absence of activity** using timers, not heartbeat signals.

---

## Module Structure

```
lib/ichor/plugins/pipeline_health_monitor/
  supervisor.ex          # DynamicSupervisor wrapper
  run_monitor.ex         # Per-run GenServer (started on mes_run_started)
  subscriber.ex          # Global subscriber — listens for run starts to spawn monitors
  score.ex               # Pure scoring functions (no side effects)
```

---

## Supervisor Registration

Wire into `lib/ichor/factory/lifecycle_supervisor.ex` children list:

```elixir
{Ichor.Plugins.PipelineHealthMonitor.Supervisor, []},
{Ichor.Plugins.PipelineHealthMonitor.Subscriber, []},
```

Add `Ichor.Plugins.PipelineHealthMonitor.Supervisor` as a named `DynamicSupervisor`:

```elixir
defmodule Ichor.Plugins.PipelineHealthMonitor.Supervisor do
  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_monitor(run_id, session) do
    DynamicSupervisor.start_child(__MODULE__, {
      Ichor.Plugins.PipelineHealthMonitor.RunMonitor,
      run_id: run_id, session: session
    })
  end
end
```

---

## Subscriber (Global)

```elixir
defmodule Ichor.Plugins.PipelineHealthMonitor.Subscriber do
  use GenServer
  alias Ichor.Signals
  alias Ichor.Signals.Message

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:mes)   # catches mes_run_started
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Message{name: :mes_run_started, data: %{run_id: run_id, session: session}}, state) do
    Ichor.Plugins.PipelineHealthMonitor.Supervisor.start_monitor(run_id, session)
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message{}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}
end
```

---

## RunMonitor GenServer State

```elixir
defmodule Ichor.Plugins.PipelineHealthMonitor.RunMonitor do
  use GenServer, restart: :temporary

  @tick_ms 10_000
  @degraded_threshold 0.5

  defstruct [
    :run_id,
    :session,
    :started_at,
    stalled_agents: [],      # [session_id]
    absent_workers: [],      # [agent_id]
    entropy_spikes: 0,       # count since last reset
    last_activity_at: nil,   # DateTime.t()
    score: 1.0               # 0.0–1.0
  ]
```

### init/1

```elixir
def init(opts) do
  run_id = Keyword.fetch!(opts, :run_id)
  Signals.subscribe(:mes)      # mes_agent_stopped
  Signals.subscribe(:agent)    # nudge_escalated, agent_evicted
  Signals.subscribe(:gateway)  # entropy_alert
  Signals.subscribe(:fleet)    # run_complete, agent_evicted
  Process.send_after(self(), :tick, @tick_ms)
  {:ok, %__MODULE__{run_id: run_id, session: Keyword.fetch!(opts, :session), started_at: DateTime.utc_now(), last_activity_at: DateTime.utc_now()}}
end
```

### handle_info clauses

| Signal | Effect |
|---|---|
| `%Message{name: :nudge_escalated}` | append to `stalled_agents` |
| `%Message{name: :agent_evicted}` | append to `stalled_agents` |
| `%Message{name: :mes_agent_stopped}` | append to `absent_workers` |
| `%Message{name: :entropy_alert}` | increment `entropy_spikes` |
| `%Message{name: :run_complete, data: %{run_id: ^run_id}}` | emit `run_health_finalized`, stop |
| `:tick` | recompute score, emit `health_score_updated`, reschedule |

Filter all signals by matching `run_id` from `data` when available. For fleet-wide signals without `run_id`, use `session` from `data` to correlate.

### Score Computation (`score.ex`, pure)

```elixir
defmodule Ichor.Plugins.PipelineHealthMonitor.Score do
  @doc "Returns 0.0–1.0 health score. Pure function."
  @spec compute(map()) :: float()
  def compute(state) do
    stall_penalty = min(length(state.stalled_agents) * 0.15, 0.45)
    absence_penalty = min(length(state.absent_workers) * 0.10, 0.30)
    entropy_penalty = min(state.entropy_spikes * 0.05, 0.25)
    max(0.0, 1.0 - stall_penalty - absence_penalty - entropy_penalty)
  end
end
```

### Emit pattern on `:tick`

```elixir
def handle_info(:tick, state) do
  score = Score.compute(state)
  Signals.emit(:health_score_updated, %{
    run_id: state.run_id,
    score: score,
    components: %{
      stalled_agents: length(state.stalled_agents),
      absent_workers: length(state.absent_workers),
      entropy_spikes: state.entropy_spikes
    }
  })

  if score < @degraded_threshold do
    Signals.emit(:pipeline_degraded, %{run_id: state.run_id, reason: :score_below_threshold, score: score})
  end

  Process.send_after(self(), :tick, @tick_ms)
  {:noreply, %{state | score: score}}
end
```

---

## Registry

Register each `RunMonitor` via `Registry`:

```elixir
Registry.register(Ichor.Registry, {:health_monitor, run_id}, %{})
```

Use `via_tuple = {:via, Registry, {Ichor.Registry, {:health_monitor, run_id}}}` as GenServer name so `run_complete` can also be handled via targeted shutdown if needed.

---

## Key Constraints

- RunMonitor must use `restart: :temporary` — if the run dies, the monitor should not restart.
- All handle_info clauses must have a catch-all `%Message{}` clause and a bare `_msg` clause to prevent crash on irrelevant signals.
- Score is pure and stateless — all side effects (emit, timer) are in RunMonitor.
- Do NOT query `Ichor.Factory.Runner` from within the plugin — react to signals only.
- New signals (`health_score_updated`, `pipeline_degraded`, `run_health_finalized`) must be added to Catalog before emitting or `Signals.emit/2` will raise.

---

## Verification

```bash
mix compile --warnings-as-errors
# Smoke test in iex:
# iex> Ichor.Signals.emit(:mes_run_started, %{run_id: "test-1", session: "ichor-test-1"})
# iex> Process.sleep(1000)
# iex> Ichor.Signals.emit(:run_complete, %{kind: :mes, run_id: "test-1", session: "ichor-test-1"})
```
