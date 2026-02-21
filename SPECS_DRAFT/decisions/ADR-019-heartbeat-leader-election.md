---
id: ADR-019
title: Heartbeat and Leader Election for Gateway
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-013
superseded_by: null
---
# ADR-019 Heartbeat and Leader Election for Gateway
[2026-02-21] proposed

## Related ADRs
- [ADR-013](ADR-013-hypervisor-platform-scope.md) Hypervisor Platform Scope (parent)
- [ADR-020](ADR-020-webhook-retry-dlq.md) Webhook Reliability: Retry + DLQ

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.1 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | Heartbeat tracking, Cron + leader election |

## Context

The Hypervisor Gateway has two time-driven responsibilities:

1. **Heartbeat tracking** — Agents send a small "ping" every N seconds. The Gateway must evict dead nodes from the Capability Map when heartbeats stop. In a single-instance deployment this is straightforward. In a multi-instance deployment, all Gateway instances receive pings; only one should own the eviction timer.

2. **Cron dispatch** — The Gateway schedules recurring tasks (and one-time agent-requested tasks). If multiple Gateway instances each run the scheduler, every scheduled event fires N times — once per instance. Leader election ensures only one instance dispatches at a time.

The brief specifies: "To prevent multiple Gateway instances from running the same cron job, use a Leader Election or Distributed Locking mechanism (e.g., via Redis or NATS). Only the 'leader' instance of the Gateway dispatches the job."

## Options Considered

**Heartbeat storage:**

A. **ETS per-instance** — Each Gateway instance tracks heartbeats for the agents connected to it. Eviction is local.
   - Con: In multi-instance deployment, an agent's heartbeats may go to Instance A while Instance B has stale data. Instance B may incorrectly evict the agent.

B. **SQLite shared table** — All instances write heartbeats to a shared DB. A single eviction timer reads from the DB.
   - Pro: Works with existing SQLite setup. Single source of truth.
   - Con: SQLite does not support concurrent writes efficiently. Write contention at high heartbeat frequency (>50 agents).

C. **ETS with per-agent leader ownership** — Leader election assigns each agent's heartbeat tracking to one instance. Ownership changes if the owning instance dies.
   - Overkill for v1.

**Leader election mechanism:**

X. **Erlang distributed cluster (`:global` or `:pg`)** — Use Erlang's built-in distributed process groups for leader election.
   - Pro: Zero external dependencies. Works today.
   - Con: Requires distributed Erlang node configuration. More ops overhead.

Y. **Single-instance GenServer (no election)** — Accept that v1 is single-instance. Document the constraint. Design the module interfaces so election can be added later.
   - Pro: Simplest correct solution for the actual current deployment.
   - Con: Not multi-instance safe.

Z. **Redis SETNX for distributed lock** — Standard distributed lock pattern. Leader holds a lock with TTL; renews every 30s. If leader dies, lock expires and a new leader acquires it.
   - Pro: Industry standard. Works across Erlang nodes and non-Erlang instances.
   - Con: Adds Redis as a dependency.

## Decision

**Phase 1: Option Y + B** — Single-instance GenServer with SQLite heartbeat storage.

**Phase 2: Option Z** — Redis-based leader election when multi-instance deployment is needed.

**Phase 1 design (built for Phase 2 migration):**

```elixir
# lib/observatory/gateway/heartbeat_manager.ex
defmodule Observatory.Gateway.HeartbeatManager do
  use GenServer

  # Called by agent on each heartbeat ping
  def record_heartbeat(agent_id, cluster_id) do
    GenServer.cast(__MODULE__, {:heartbeat, agent_id, cluster_id, DateTime.utc_now()})
  end

  # GenServer state: %{agent_id => %{last_seen: datetime, cluster_id: string}}
  # Every 30s: find agents where last_seen > 90s ago → evict from Capability Map
  def handle_info(:check_heartbeats, state) do
    now = DateTime.utc_now()
    dead = Enum.filter(state.agents, fn {_id, %{last_seen: t}} ->
      DateTime.diff(now, t, :second) > 90
    end)
    Enum.each(dead, fn {agent_id, _} -> evict_agent(agent_id) end)
    {:noreply, Map.drop(state, Enum.map(dead, &elem(&1, 0)))}
  end
end
```

**Phase 2 interface contract:** The public API (`record_heartbeat/2`, heartbeat config) does not change. Only the leader-election wrapper changes internally. This is why the interface is specified now even though the implementation is simple.

**Cron scheduler (Phase 1):**
```elixir
# lib/observatory/gateway/cron_scheduler.ex
# Simple GenServer. In Phase 1: single-instance, no election.
# Reads cron table from SQLite on start. Fires jobs via PubSub.
# Supports dynamic one-time entries: schedule_once(agent_id, delay_ms, payload)
```

**Dynamic agent scheduling:** An agent sends a special DecisionLog message with `action.tool_call == "schedule_reminder"` and `action.tool_input` containing the delay. The Gateway's Schema Interceptor recognizes this as a scheduler command and calls `CronScheduler.schedule_once/3`. The reminder fires as a new message injected into the agent's session.

**Heartbeat ping format** (from agent to Gateway):
```json
{
  "type": "heartbeat",
  "agent_id": "researcher-alpha-9",
  "cluster_id": "mesh-04",
  "timestamp": "iso-8601-utc"
}
```

## Rationale

Committing to Redis in Phase 1 for a feature not yet needed adds operational cost with no benefit. The existing AgentMonitor GenServer (already deployed) already tracks agent heartbeats via event timestamps. `HeartbeatManager` replaces it with an explicit ping channel rather than inferring liveness from tool events — a more reliable signal.

The Phase 2 Redis path is common enough that no architectural dead ends exist in Phase 1. The GenServer interface does not need to change; only the leader election wrapper needs to be added around the cron dispatch.

## Consequences

- New module: `lib/observatory/gateway/heartbeat_manager.ex` (replaces AgentMonitor for liveness)
- New module: `lib/observatory/gateway/cron_scheduler.ex` (periodic + one-time jobs)
- SQLite table: `gateway_heartbeats (agent_id, cluster_id, last_seen_at)`
- SQLite table: `cron_jobs (id, agent_id, schedule, next_fire_at, payload, is_one_time)`
- New HTTP endpoint: `POST /gateway/heartbeat` — agents ping here
- Capability Map (new module) updated by HeartbeatManager on eviction
- Phase 2 trigger: when multi-instance deployment is required, add Redis SETNX leader election as a wrapper around CronScheduler dispatch
