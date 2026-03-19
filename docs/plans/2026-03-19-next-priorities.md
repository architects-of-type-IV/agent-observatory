# Plan: Next Session Priorities (codex-reviewed 2026-03-19)

## Context

Session 2 completed: physical file reorg (136 renames), deep audits (4 reports), MES topology restore, bug fixes. Codex analyzed all findings and recommended priority order. This plan covers immediate fixes and the next session's architecture work.

## Immediate Fix: Duplicate Signals

**Root cause (two layers):**
1. `Phoenix.PubSub.subscribe` is additive -- `apply_nav_view(:signals)` adds a subscription on every navigation. After N visits → N copies.
2. `broadcast_static` publishes to two PubSub topics (category + signal-specific). Potential for double receipt if any subscriber listens to both.

**Fix:** Dedup at `MessageRouter.send/1` -- hash message content before delivery. If same hash was sent within a time window, skip. Idempotent at the source, not the consumer.

**Files to investigate:**
- `lib/ichor/message_router.ex` -- add content hash dedup
- `lib/ichor/signals/runtime.ex` -- `broadcast_static/2` dual-topic publish
- `lib/ichor/signals/buffer.ex` -- verify single subscription path
- `lib/ichor_web/live/dashboard_live.ex` -- additive subscribe (secondary issue)

## Next Session Priority Order (codex-recommended)

### 1. Consolidate RunProcess lifecycles + spawn chains
- Unify BuildRunner, PlanRunner, RunProcess into one runtime lifecycle abstraction
- Route all spawn paths (MES, Genesis, DAG) through Workshop presets + TeamLaunch
- One runtime contract, one supervisor pattern, one cleanup path, one signaling model
- **Why first:** Largest blast-radius reducer. Everything else gets easier after.

### 2. Finish registry redesign
- Remove remaining 15 AgentRegistry references
- Complete the single-source-of-truth Registry model

### 3. Break dependency cycles (as byproduct of consolidation)
- 14-node Control cycle, 6-node Projects cycle, 4-node lifecycle cycle
- Don't attack standalone -- they're symptoms of duplicated orchestration

### 4. Remove ~100 domain wrapper functions
- Replace hand-written wrappers in control.ex, projects.ex, observability.ex with Ash `define` on resources
- Do AFTER architecture stabilizes (wrappers are boundary cleanup, not structural)

### 5. Quality audit gaps
- @enforce_keys, dead notifiers (FromAsh on virtual Task), impure GenesisFormatter.to_map
- Unsafe String.to_existing_atom (2 callsites)
- Triplicated EventBuffer reader

### 6. Component library (DEFER)
- 12 duplicated badge patterns, but UI primitives land after backend stops shifting

## Verification
- `mix compile --warnings-as-errors`
- `mix credo --strict`
- MES team spawn + full run completion
- Signal livefeed shows no duplicates after fix

## Design: MessageRouter (Plain Module)

Iron Law check: no mutable state, no concurrency, no fault isolation needed. **Plain module, not GenServer.**

```
MessageRouter.send(%{from: "operator", to: "dag-123-coordinator", content: "...", type: :text})
  |> resolve_target()           # normalize "team:alpha" / "session:abc" / "operator" / raw id
  |> deliver(target, message)   # AgentProcess.send_message + Tmux.deliver
  |> log_delivery()             # ETS message log (replaces Comms.tap_delivery)
  |> emit_signal()              # :message_delivered signal
  |> return {:ok, %{delivered: N, to: target}}
```

### Public API

One function:

```elixir
@spec send(map()) :: {:ok, map()} | {:error, term()}
def send(%{from: from, to: to, content: content} = attrs)
```

Optional keys: `type` (default `:text`), `metadata` (default `%{}`).

### Target Resolution (Pure)

Extract from existing `Fleet.Comms` + `Gateway.Target`:

```elixir
defp resolve_target("team:" <> name),   do: {:team, name}
defp resolve_target("fleet:" <> _),     do: {:fleet, :all}
defp resolve_target("role:" <> role),   do: {:role, role}
defp resolve_target("session:" <> sid), do: {:session, sid}
defp resolve_target(id),               do: {:agent, id}
```

### Delivery (Side Effect Boundary)

```elixir
defp deliver({:agent, id}, msg),  do: deliver_to_agent(id, msg)
defp deliver({:session, sid}, msg), do: deliver_to_agent(sid, msg)
defp deliver({:team, name}, msg), do: deliver_to_team(name, msg)
defp deliver({:fleet, :all}, msg), do: deliver_to_fleet(msg)
defp deliver({:role, role}, msg), do: deliver_to_role(role, msg)
```

`deliver_to_agent` calls `AgentProcess.send_message/2` directly. No configurable module indirection. If agent not alive, falls back to direct `Tmux.deliver` via Registry lookup.

### Signal Emission

After every delivery: `Signals.emit(:message_delivered, %{agent_id: id, msg_map: normalized_msg})`

This preserves the existing signal contract that `Genesis.RunProcess`, `Dag.RunProcess`, and `Mes.ProjectIngestor` depend on for completion detection.

### ETS Message Log

Move `record_message` from `Comms` into `MessageRouter`. Every message goes through one path, so every message gets logged. No more inconsistency between Comms path (logged) and Gateway path (not logged).

## Files to Create

### NEW: `lib/ichor/message_router.ex` (~120 lines)

Plain module. Single `send/1` function. Contains:
- `send/1` -- entry point, validates attrs, normalizes message, resolves target, delivers, logs, emits signal
- `resolve_target/1` -- pure pattern matching on target string
- `deliver/2` -- dispatches by target type to `deliver_to_agent`, `deliver_to_team`, `deliver_to_fleet`, `deliver_to_role`
- `deliver_to_agent/2` -- `AgentProcess.send_message` + tmux fallback
- `deliver_to_team/2` -- `TeamSupervisor.member_ids` -> deliver each
- `deliver_to_fleet/1` -- `AgentProcess.list_all` -> deliver each
- `deliver_to_role/2` -- `AgentProcess.list_all` -> filter by role -> deliver each
- `normalize_message/1` -- adds id, timestamp, defaults
- `log_delivery/3` -- ETS `:ichor_message_log` write
- `emit_delivered/2` -- `Signals.emit(:message_delivered, ...)`

### NEW: `lib/ichor/message_router/target.ex` (~30 lines)

Pure target resolution. Extracted from `Gateway.Target` -- pattern matching only, no side effects.

## Files to Modify

### `lib/ichor/agent_tools/inbox.ex` -- MCP send_message action

Replace:
```elixir
Messaging.send_as_agent(from, to, content)
```
With:
```elixir
MessageRouter.send(%{from: from, to: to, content: content, type: :message})
```

### `lib/ichor/operator.ex` -- Remove send delegation

Remove `send/2` and `send/3` from Operator entirely. Operator keeps its other responsibilities (message log, Registry, ETS) but no longer owns sending. All LiveView handlers call `MessageRouter.send` directly.

### `lib/ichor/archon/tools/messages.ex` -- Archon send_message

Replace `Messaging.send_as_operator(to, content)` with `MessageRouter.send(%{from: "archon", to: to, content: content})`.

### `lib/ichor_web/live/dashboard_messaging_handlers.ex` -- all send handlers

Replace all `Operator.send(target, content, opts)` calls with `MessageRouter.send(%{from: "operator", to: target, content: content, type: opts[:type] || :text, metadata: opts[:metadata] || %{}})`.

### `lib/ichor_web/live/dashboard_session_control_handlers.ex` -- pause/resume/shutdown

Replace `Operator.send(session_id, msg, type: :session_control, metadata: %{action: action})` with `MessageRouter.send(%{from: "operator", to: session_id, content: msg, type: :session_control, metadata: %{action: action}})`.

### `lib/ichor_web/live/dashboard_dag_handlers.ex` -- DAG command panel

Replace `Operator.send(to, content)` with `MessageRouter.send(%{from: "operator", to: to, content: content})`.

### `lib/ichor/quality_gate.ex` -- nudge_agent

Replace `Comms.notify_session(session_id, message, ...)` with `MessageRouter.send(%{from: "ichor", to: session_id, content: message, type: :quality_gate})`.

### `lib/ichor/nudge_escalator.ex` -- do_escalate level 1

Replace `Comms.notify_session(...)` with `MessageRouter.send(%{from: "ichor", to: tmux_target, content: nudge_message, type: :nudge})`.

### `lib/ichor_web/controllers/gateway_rpc_controller.ex` -- HTTP RPC

Replace `Gateway.Router.broadcast(channel, payload)` with `MessageRouter.send(%{from: payload["from"] || "external", to: channel, content: payload["content"]})`.

## Files to Delete

### `lib/ichor/tools/messaging.ex`

Fully replaced by MessageRouter. Zero callers remain after modifications above.

### `lib/ichor/fleet/comms.ex`

Fully replaced by MessageRouter. The ETS message log moves to MessageRouter. `Comms.recent_messages/1` becomes `MessageRouter.recent_messages/1`. `start_message_log/0` moves to MessageRouter or Application.

## Files to Keep (no changes)

- `lib/ichor/fleet/agent_process.ex` -- inbox state, `send_message/2`, `get_unread/1`. These are the delivery target, not the routing layer.
- `lib/ichor/fleet/agent_process/delivery.ex` -- normalizes messages inside AgentProcess, delivers to tmux backend
- `lib/ichor/fleet/agent_process/mailbox.ex` -- manages unread state, routes to backend
- `lib/ichor/gateway/router.ex` -- keeps event ingest, schema validation, topology. Outbound messaging moves to MessageRouter.
- `lib/ichor/gateway/channels/tmux.ex` -- tmux paste delivery, called by MessageRouter for fallback
- `lib/ichor/gateway/channels/mailbox_adapter.ex` -- may become unused (MessageRouter calls AgentProcess directly)

## Callers Inventory (21 callers -> 1 API)

| # | Caller | File | Currently calls | New call |
|---|--------|------|-----------------|----------|
| 1 | Dashboard send agent msg | dashboard_messaging_handlers.ex:13 | Operator.send | MessageRouter.send |
| 2 | Dashboard team broadcast | dashboard_messaging_handlers.ex:37 | Operator.send | MessageRouter.send |
| 3 | Dashboard push context | dashboard_messaging_handlers.ex:52 | Operator.send | MessageRouter.send |
| 4 | Dashboard targeted msg | dashboard_messaging_handlers.ex:85 | Operator.send | MessageRouter.send |
| 5 | Dashboard DAG command | dashboard_dag_handlers.ex:97 | Operator.send | MessageRouter.send |
| 6 | Dashboard pause agent | dashboard_session_control_handlers.ex:34 | Operator.send | MessageRouter.send |
| 7 | Dashboard resume agent | dashboard_session_control_handlers.ex:55 | Operator.send | MessageRouter.send |
| 8 | Dashboard shutdown agent | dashboard_session_control_handlers.ex:103 | Operator.send | MessageRouter.send |
| 9 | MCP send_message | agent_tools/inbox.ex:73 | Messaging.send_as_agent | MessageRouter.send |
| 10 | Archon send_message | archon/tools/messages.ex:60 | Messaging.send_as_operator | MessageRouter.send |
| 11 | QualityGate nudge | quality_gate.ex:123 | Comms.notify_session | MessageRouter.send |
| 12 | NudgeEscalator level 1 | nudge_escalator.ex:173 | Comms.notify_session | MessageRouter.send |
| 13 | Gateway RPC | gateway_rpc_controller.ex:16 | Router.broadcast | MessageRouter.send |
| 14 | Fleet.Agent :send_message | fleet/agent.ex:209 | RuntimeHooks.send_agent_message | MessageRouter.send |

All 14 callers go directly to `MessageRouter.send`. No wrappers, no delegation.

## Signal Contract (Preserved)

`:message_delivered` signal shape stays identical:
```elixir
%{agent_id: String.t(), msg_map: %{id:, to:, from:, content:, type:, timestamp:, metadata:}}
```

`Genesis.RunProcess`, `Dag.RunProcess`, and `Mes.ProjectIngestor` continue subscribing and pattern-matching on this signal. No changes needed.

## Verification

1. `mix compile --warnings-as-errors` -- clean build
2. `mix credo --strict` -- clean
3. Test MCP send_message: `curl -s -X POST http://localhost:4005/mcp -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"tools/call","id":1,"params":{"name":"send_message","arguments":{"input":{"from_session_id":"test","to_session_id":"operator","content":"test"}}}}'`
4. Test Operator.send from dashboard: send a message to an agent from the comms panel
5. Test completion detection: spawn a Genesis Mode B team, verify RunProcess detects coordinator -> operator delivery and disbands the team
6. Verify ETS message log: `Ichor.MessageRouter.recent_messages(20)` returns messages from all paths
