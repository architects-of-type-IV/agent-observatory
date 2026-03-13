# Project Brief: Ichor.Execution — Structured Workflow Execution Engine

**Run ID:** adcfb38a
**Date:** 2026-03-13
**Status:** Draft (coordinator fallback)

---

## Description

`Ichor.Execution` is a structured workflow execution engine for ICHOR IV. It provides
deterministic, observable execution of multi-step agent workflows — think DAG-based job
pipelines with first-class OTP supervision, signal emission at each stage transition, and
a persistent execution ledger backed by Ecto/Postgres.

The subsystem fills the gap between the Signals nervous system (event routing) and the
Fleet layer (agent processes): it gives the control plane a durable, replayable record of
*what ran*, *in what order*, and *what it produced* — independent of which agent or tmux
session executed it.

---

## Motivation

Current ICHOR IV has rich real-time observability (Signals, EventBuffer, Feed) but no
durable execution record. When an agent completes a multi-step task:

- There is no queryable history of which steps ran and their outcomes
- Retry logic is ad-hoc per agent
- Parallel step fan-out has no coordination primitive
- The dashboard cannot show structured progress for long-running workflows

`Ichor.Execution` closes these gaps with a lightweight, OTP-native engine.

---

## Subsystem Module Name

```
Ichor.Execution
```

### Top-level modules

| Module | Responsibility |
|--------|---------------|
| `Ichor.Execution` | Public API (`run/2`, `status/1`, `cancel/1`) |
| `Ichor.Execution.Workflow` | Ash Resource — persistent workflow definition |
| `Ichor.Execution.Run` | Ash Resource — one execution instance of a workflow |
| `Ichor.Execution.Step` | Ash Resource — individual step record within a run |
| `Ichor.Execution.Engine` | GenServer — runs steps, manages DAG fan-out |
| `Ichor.Execution.Supervisor` | DynamicSupervisor — one Engine per active Run |
| `Ichor.Execution.StepRunner` | Task.Supervisor-backed step executor |

---

## Signal Interface

All signals emitted under the `execution` category via `Ichor.Signals.emit/2`.

### Emitted Signals

| Signal Name | Kind | Payload |
|-------------|------|---------|
| `execution.run.started` | `:event` | `%{run_id, workflow_id, session_id, step_count}` |
| `execution.run.completed` | `:event` | `%{run_id, workflow_id, duration_ms, result}` |
| `execution.run.failed` | `:event` | `%{run_id, workflow_id, step_id, reason}` |
| `execution.run.cancelled` | `:event` | `%{run_id, workflow_id, cancelled_by}` |
| `execution.step.started` | `:event` | `%{run_id, step_id, step_name, attempt}` |
| `execution.step.completed` | `:event` | `%{run_id, step_id, step_name, duration_ms}` |
| `execution.step.failed` | `:event` | `%{run_id, step_id, step_name, reason, attempt}` |
| `execution.step.retrying` | `:event` | `%{run_id, step_id, step_name, attempt, backoff_ms}` |

### Subscribed Signals

| Signal | Handler |
|--------|---------|
| `fleet.agent.terminated` | Cancel any runs owned by the terminated session |
| `signals.system.heartbeat` | Sweep for stale/stuck runs (> configurable TTL) |

### Catalog Registration

```elixir
# In Ichor.Signals.Catalog
category :execution do
  signal :run_started,   kind: :event, schema: ExecutionRunStarted
  signal :run_completed, kind: :event, schema: ExecutionRunCompleted
  signal :run_failed,    kind: :event, schema: ExecutionRunFailed
  signal :run_cancelled, kind: :event, schema: ExecutionRunCancelled
  signal :step_started,  kind: :event, schema: ExecutionStepStarted
  signal :step_completed,kind: :event, schema: ExecutionStepCompleted
  signal :step_failed,   kind: :event, schema: ExecutionStepFailed
  signal :step_retrying, kind: :event, schema: ExecutionStepRetrying
end
```

---

## Key Design Decisions

1. **OTP-native execution** — each active Run gets a supervised `Engine` GenServer.
   Crash isolation is per-run, not per-workflow. Supervisor restart restores in-progress runs
   from the Ecto ledger on startup.

2. **DAG step ordering** — steps declare `depends_on: [step_id]`; Engine fans out
   all ready steps via `Task.Supervisor`. No polling — steps signal completion back to Engine
   via `GenServer.cast`.

3. **Ash-backed ledger** — `Run` and `Step` are Ash Resources with Postgres persistence.
   Enables `Repo.all(Run, filter: [status: :running])` sweep on boot for crash recovery.

4. **No global state** — `Ichor.Execution` public API looks up the Engine PID via
   `Ichor.Fleet.ProcessRegistry`; no ETS global table.

5. **Signal-first observability** — every state transition emits a signal. Dashboard and
   Feed pick up execution progress without polling or direct DB queries.

---

## Dashboard Integration

- New view mode `:execution` (keyboard: `e`) showing active and recent runs
- Fleet tree: agents with active runs show a step-progress badge
- Feed: `execution.step.*` signals render as structured timeline entries

---

## Acceptance Criteria

- [ ] `mix compile --warnings-as-errors` passes
- [ ] `Ichor.Execution.run/2` starts a supervised Engine for a given workflow
- [ ] Step DAG fan-out executes parallel steps concurrently via Task.Supervisor
- [ ] All 8 signals registered in `Signals.Catalog` under `:execution` category
- [ ] Run/Step Ash Resources persist to Postgres with correct status transitions
- [ ] Crash recovery: restarted Engine resumes in-progress run from DB state
- [ ] Dashboard `:execution` view mode renders active runs
