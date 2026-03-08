# ADR-025: Native BEAM Messaging

> Status: PROPOSED | Date: 2026-03-08

## Context

ICHOR IV currently has 5 messaging paths, three of which bypass the Gateway entirely:

| Path | Flow | Bypasses Gateway? |
|------|------|-------------------|
| **A. Dashboard** | LiveView -> Operator.send -> Gateway.Router.broadcast -> Channels | No |
| **B. Hook event** | EventController -> Router.ingest -> PubSub | Partially (ingest only) |
| **C. MCP send** | AgentTools.send_message -> Gateway.Router.broadcast | No |
| **D. MCP inbox** | AgentTools.check_inbox -> Mailbox.get_messages (ETS direct) | Yes |
| **E. CommandQueue** | Disk write -> poll-based pickup | Yes |

The CommandQueue path (E) is the primary delivery mechanism for external agents. Messages are written as JSON files to `~/.claude/inbox/{session_id}/{id}.json` and the agent polls via MCP `check_inbox`. This is a filesystem-based message queue -- the exact problem that BEAM process mailboxes solve natively.

The Mailbox (D) is an ETS table acting as a store-and-forward buffer. Agents poll it via MCP. There is no push notification -- the agent must ask "do I have messages?" on a timer.

With agent processes (ADR-023), each agent has a native BEAM mailbox. Messages can be pushed via `GenServer.cast`. The question is how to unify the 5 paths into one.

## Decision

### Single Messaging Path

All messages flow through agent processes. The agent process is the delivery target for all communication.

```
Any sender (Dashboard, MCP, Agent, System)
  -> Observatory.Fleet.AgentProcess.send_message(target_id, message)
  -> GenServer.cast(via(target_id), {:message, message})
  -> AgentProcess.handle_cast({:message, msg}, state):
       1. Store in process state (recent messages buffer)
       2. Forward to backend (tmux paste, SSH, webhook, MCP response)
       3. Broadcast on PubSub for dashboard observation
```

### Pattern-Based Routing

The Gateway Router retains its role for pattern-based addressing (`"team:frontend"`, `"fleet:all"`, `"role:worker"`). But instead of iterating channels per recipient, it resolves patterns to agent IDs and casts to each:

```elixir
def broadcast(pattern, payload) do
  agent_ids = resolve_pattern(pattern)  # Registry.select or match

  Enum.each(agent_ids, fn id ->
    AgentProcess.send_message(id, payload)
  end)

  {:ok, length(agent_ids)}
end

defp resolve_pattern("team:" <> name) do
  TeamSupervisor.member_ids(name)
end

defp resolve_pattern("fleet:all") do
  Registry.select(Fleet.AgentRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
end

defp resolve_pattern("agent:" <> id), do: [id]
```

The Router no longer touches channels. Channel selection is the agent process's responsibility (it knows its own backend).

### MCP Integration

External agents (those using MCP `check_inbox`) still need a way to receive messages. Two approaches, depending on agent capabilities:

**A. Server-Sent Events (preferred).** The agent opens an SSE connection to ICHOR. Messages are pushed as events. The agent process writes to the SSE stream when it receives a message.

**B. Poll endpoint (backward compatible).** `check_inbox` reads from the agent process's message buffer instead of Mailbox ETS. The agent process stores recent unread messages in its state. `check_inbox` calls `AgentProcess.get_unread(agent_id)`.

```elixir
# In AgentProcess
def handle_call(:get_unread, _from, state) do
  {:reply, state.unread_messages, %{state | unread_messages: []}}
end
```

This preserves the MCP polling contract but eliminates the CommandQueue filesystem and Mailbox ETS table. The data lives in the agent process -- the only source of truth for that agent's state.

### What Gets Eliminated

| Component | Replaced By |
|-----------|-------------|
| `Observatory.CommandQueue` | Agent process mailbox (GenServer state) |
| `Observatory.Mailbox` (ETS) | Agent process mailbox (GenServer state) |
| `~/.claude/inbox/` filesystem | Gone. No disk I/O for messaging. |
| 5 messaging paths | 1 path: `AgentProcess.send_message/2` |
| Channel iteration in Router | Channel selection in AgentProcess |
| `Operator.send` fallback logic | Gone. Router resolves, AgentProcess delivers. |

### Message Format

Messages in the agent process are Elixir maps, not JSON files:

```elixir
%{
  id: "msg-uuid",
  from: "architect" | "agent-id" | "system",
  content: "...",
  type: :instruction | :message | :nudge | :system,
  timestamp: DateTime.utc_now(),
  metadata: %{}
}
```

Serialization to JSON happens only at the boundary -- when the MCP endpoint responds to `check_inbox`, or when the tmux channel pastes content into a terminal.

### PubSub for Observation

Every message delivery broadcasts on PubSub for dashboard observation:

```elixir
Phoenix.PubSub.broadcast(Observatory.PubSub, "messages:stream", {:message_delivered, msg})
```

The dashboard subscribes to `"messages:stream"` and renders the comms timeline. This replaces the current approach of the dashboard reading from Mailbox ETS on every recompute.

## Consequences

- **One messaging path.** Dashboard, MCP, system, and inter-agent messages all go through `AgentProcess.send_message/2`.
- **No disk I/O for messaging.** Eliminates CommandQueue filesystem writes and reads.
- **No ETS for messaging.** Eliminates Mailbox GenServer and its ETS table.
- **Push delivery.** Agent processes receive messages instantly via GenServer.cast. No polling delay.
- **MCP backward compatible.** `check_inbox` reads from process state instead of ETS. Same API contract for external agents.
- **Dashboard observes via PubSub.** No more reading from Mailbox ETS on tick. Messages arrive as events.
- **Operator module simplifies.** `Operator.send/2` becomes a thin wrapper around `AgentProcess.send_message/2` for Architect-initiated messages.
- **Ordering guarantees.** GenServer mailbox is FIFO. Messages arrive in order without additional sequencing logic.
- **Crash recovery.** If an agent process crashes, undelivered messages in its mailbox are lost. For critical messages, the supervisor restarts the agent and the sender can retry. For buffered history, the PubSub broadcast means the dashboard (and any other subscriber) has already captured the message.
