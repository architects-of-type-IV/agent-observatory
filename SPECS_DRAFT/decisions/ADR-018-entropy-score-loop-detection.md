---
id: ADR-018
title: Entropy Score as Loop Detection Primitive
date: 2026-02-21
status: proposed
related_tasks: []
parent: ADR-014
superseded_by: null
---
# ADR-018 Entropy Score as Loop Detection Primitive
[2026-02-21] proposed

## Related ADRs
- [ADR-014](ADR-014-decision-log-envelope.md) DecisionLog Universal Message Envelope (parent)
- [ADR-015](ADR-015-gateway-schema-interceptor.md) Gateway Schema Interceptor
- [ADR-017](ADR-017-causal-dag-parent-step-id.md) Causal DAG via parent_step_id

## References

| Reference | Location | Notes |
|-----------|----------|-------|
| Project Brief §4.1 | [PROJECT-BRIEF.md](../PROJECT-BRIEF.md) | "Entropy Alerting: Gateway calculates this" |

## Context

Autonomous agents can enter reasoning loops: they repeat the same reasoning chain with high confidence, take the same action, receive the same failure, and repeat. Without detection, these loops consume budget indefinitely and block downstream agents waiting for output.

The project brief specifies `cognition.entropy_score` as a field in the DecisionLog schema. Two unresolved questions:
1. Who computes entropy_score — the agent or the Gateway?
2. What algorithm produces the score?
3. What threshold triggers the alert, and what happens when it fires?

## Options Considered

**Who computes it:**

A. **Agent self-reports** — Each agent computes and emits its own entropy_score in every DecisionLog message.
   - Pro: Agent has full context of its own reasoning history.
   - Con: Self-reported entropy is gameable and unreliable. An agent in a loop may not self-diagnose.

B. **Gateway computes from message history** — Gateway maintains a sliding window of recent DecisionLog messages per session. Computes entropy by comparing reasoning_chain similarity across the window.
   - Pro: External, objective measurement. Cannot be gamed by a malfunctioning agent.
   - Con: Gateway must process natural language strings (reasoning chains). Similarity computation adds latency.

C. **Hybrid: agent self-reports, Gateway validates** — Agent emits a score; Gateway independently checks a simpler heuristic (repeat action detection). If the two diverge significantly, Gateway emits a discrepancy event.
   - Pro: Two signals are better than one. Catches both agent self-detection failures and Gateway false positives.
   - Con: More complex; two thresholds to tune.

## Decision

**Phase 1: Option B (Gateway-computed)**. Phase 2: Extend to Option C if self-reporting proves valuable.

**Gateway entropy computation algorithm:**

For each session, maintain a sliding window of the last 5 `{intent, action.tool_call, action.status}` tuples. Compute a repetition score:

```elixir
def compute_entropy(session_window) do
  n = length(session_window)
  unique = session_window |> MapSet.new() |> MapSet.size()
  # entropy = 0 when all identical (pure loop), 1 when all unique
  unique / n
end
```

This is not information-theoretic entropy — it is a simpler "uniqueness ratio" that is fast to compute and interpretable. An agent repeating the same `{intent, tool_call, status: :failure}` tuple 5 times out of 5 yields entropy = 0.2 (1 unique / 5 total).

**Alert thresholds:**

| Entropy Score | Severity | UI Action |
|---------------|----------|-----------|
| < 0.25 | LOOP | Node flashes red; `EntropyAlertEvent` emitted; Session Cluster Manager flags session in "Entropy Alerts" panel |
| 0.25–0.50 | WARNING | Node highlighted amber; no alert |
| > 0.50 | Normal | No action |

**EntropyAlertEvent fields:**
```json
{
  "event_type": "entropy_alert",
  "session_id": "...",
  "agent_id": "...",
  "entropy_score": 0.2,
  "window_size": 5,
  "repeated_pattern": {"intent": "...", "tool_call": "...", "action_status": "failure"},
  "occurrence_count": 4
}
```

**HITL interaction:** When an `EntropyAlertEvent` fires, the UI presents a one-click "Pause and Inspect" button in the Session Cluster Manager. Clicking issues a `Pause` command via the HITL API (ADR-021).

**Score field in DecisionLog:** The `cognition.entropy_score` field in the schema remains. In Phase 1, the Gateway overwrites it with the computed value before broadcasting. Agents may still self-report; the Gateway's computed value is authoritative.

## Rationale

Gateway-computed entropy is preferable to self-reported because agents in loops are the least likely to accurately self-diagnose. The simple uniqueness ratio is computable in microseconds per message without any NLP overhead. It catches the primary loop pattern (same tool_call + failure repeated N times) with no false positives for genuinely diverse sessions.

The 5-message sliding window is tuned to detect loops that establish themselves in 3-5 turns without reacting to normal short repetitions (e.g., reading two files in a row).

## Consequences

- New module: `lib/observatory/gateway/entropy_tracker.ex` (ETS sliding window per session)
- `SchemaInterceptor` (ADR-015) calls `EntropyTracker.record_and_score/2` after validation
- New PubSub topic: `"gateway:entropy_alerts"` — UI subscribes for real-time alerts
- New Ash event (or ETS log): `EntropyAlertEvent`
- Topology map node state: `:alert_entropy` (flashing red)
- Session Cluster Manager "Entropy Alerts" panel shows sessions with current entropy < 0.25
- Sliding window size (5) and thresholds (0.25, 0.50) are runtime-configurable via application config
