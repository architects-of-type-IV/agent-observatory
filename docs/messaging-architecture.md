# Observatory Messaging Architecture

## Overview

Messages flow through multiple paths depending on the sender, recipient, and delivery
requirements. The Gateway Router is the intended central bus, but several legacy paths
bypass it. This document maps the current state to inform unification.

## Delivery Channels

| Channel | Backing Store | Module | Purpose |
|---------|--------------|--------|---------|
| Mailbox | ETS (`:observatory_mailboxes`) | `Observatory.Mailbox` | Primary message store, 200 msgs/agent, 24h TTL |
| CommandQueue | Filesystem (`~/.claude/inbox/`) | `Observatory.CommandQueue` | Durable file-based delivery for Claude agent polling |
| Tmux | Terminal keystroke injection | `Gateway.Channels.Tmux` | Push messages into agent terminal sessions |
| Webhook | Postgres (`webhook_deliveries`) | `Gateway.WebhookRouter` | Durable HTTP delivery with exponential backoff |

All channels are **additive** -- Mailbox always fires; Tmux, Webhook fire alongside when configured.

## Agent Registration (AgentRegistry)

ETS table `:gateway_agent_registry`. Agents enter via:

1. **Hook events** -- `POST /api/events` -> `Router.ingest` -> `AgentRegistry.register_from_event`
2. **TeamWatcher sync** -- PubSub `"teams:update"` -> `AgentRegistry.sync_teams`
3. **Tmux polling** -- Every 5s, discovers new tmux sessions
4. **Operator** -- Permanent entry at init: `id: "operator"`, `channels.mailbox: "operator"`

Agents are swept after 2h in `:ended` status.

## Message Flows

### Path A: Operator -> Agent (via Gateway)

```
Dashboard form (phx-submit)
  -> DashboardLive.handle_event
  -> Handler module (MessagingHandlers / TeamInspectorHandlers / SwarmHandlers)
  -> Observatory.Operator.send(target, content)
  -> Operator.normalize_target (resolves channel pattern)
  -> Gateway.Router.broadcast(channel, payload)
     Pipeline: Validate -> Route -> Deliver -> Audit
     -> SchemaInterceptor.validate_envelope
     -> AgentRegistry.resolve_channel (returns agent structs)
     -> For each agent:
        -> MailboxAdapter.deliver -> Mailbox.send_message
           -> ETS insert
           -> CommandQueue.write_command (filesystem)
           -> PubSub "agent:{session_id}" {:new_mailbox_message, msg}
        -> Tmux.deliver (if tmux channel set)
        -> WebhookAdapter.deliver (if webhook channel set)
     -> ProtocolTracker.track_gateway_broadcast
     -> PubSub "gateway:audit"
```

### Path B: Agent -> Operator (via MCP)

```
Agent calls MCP send_message {to_session_id: "operator", content: "..."}
  -> AshAi MCP Router
  -> AgentTools.Inbox :send_message action
  -> Gateway.Router.broadcast("agent:operator", payload)
     -> AgentRegistry resolves "operator" -> permanent entry
     -> MailboxAdapter.deliver("operator", payload)
        -> Mailbox.send_message -> ETS + CommandQueue + PubSub "agent:operator"
  -> DashboardLive receives {:new_mailbox_message, msg}
     (subscribed to "agent:operator" at mount)
```

### Path C: Agent -> Agent (via MCP)

```
Agent A calls MCP send_message {to_session_id: "agent_b_sid", content: "..."}
  -> Gateway.Router.broadcast("agent:agent_b_sid", payload)
     -> Same pipeline as Path A
  -> Agent B reads via:
     - File polling: ~/.claude/inbox/{session_id}/
     - MCP check_inbox -> Mailbox.get_messages (ETS)
     - MCP acknowledge_message -> Mailbox.mark_read + file cleanup
```

### Path D: Agent -> Dashboard (via Hook Event)

```
Agent fires SendMessage tool (intercepted by hook)
  -> POST /api/events
  -> EventController.handle_pre_tool_use
  -> handle_send_message:
     type "message" -> Mailbox.send_message (BYPASSES Gateway)
     type "broadcast" -> Channels.publish_to_team (PubSub only)
```

### Path E: Session Control (BYPASSES Gateway)

```
Dashboard pause/resume/shutdown buttons
  -> DashboardSessionControlHandlers
  -> CommandQueue.write_command + Mailbox.send_message (direct calls)
  -> Does NOT go through Operator or Gateway Router
```

## Bypass Paths (Gateway NOT Used)

These paths write to Mailbox/CommandQueue directly, skipping Gateway validation,
routing, audit trail, and protocol tracking:

| Path | Module | Why It Bypasses |
|------|--------|-----------------|
| Hook SendMessage events | `EventController` line 173 | Legacy: predates Gateway |
| Pause/Resume/Shutdown | `SessionControlHandlers` | Commands, not messages |
| Kill switch | `SessionControlHandlers` | Emergency broadcast via raw PubSub |
| Push instructions | `SessionControlHandlers` | Class-wide broadcast via raw PubSub |
| Team broadcasts (hook) | `EventController` line 187 | Uses `Channels.publish_to_team` directly |

## PubSub Topics (Message-Related)

| Topic | Shape | Publisher | Subscriber |
|-------|-------|-----------|------------|
| `"agent:{sid}"` | `{:new_mailbox_message, msg}` | Mailbox | DashboardLive, agents |
| `"agent:operator"` | `{:new_mailbox_message, msg}` | Mailbox | DashboardLive (mount) |
| `"gateway:audit"` | `{:gateway_audit, entry}` | Router | (unsubscribed) |
| `"gateway:messages"` | `{:decision_log, log}` | GatewayController, EventBridge, HITLRelay | DashboardGatewayHandlers |
| `"protocols:update"` | `{:message_read, data}` | Mailbox.mark_read | DashboardLive |
| `"team:{name}"` | `{:team_broadcast, msg}` | Channels | Team members |
| `"dashboard:commands"` | `{:dashboard_command, cmd}` | Channels | External agents |

## MCP Tools (Ash Resource Actions)

Domain: `Observatory.AgentTools`, Resource: `Observatory.AgentTools.Inbox`

| Tool | Action | Calls |
|------|--------|-------|
| `check_inbox` | `:check_inbox` | `Mailbox.get_messages(session_id)` |
| `acknowledge_message` | `:acknowledge_message` | `Mailbox.mark_read` + file cleanup |
| `send_message` | `:send_message` | `Gateway.Router.broadcast` |
| `get_tasks` | `:get_tasks` | `TaskManager.list_tasks` |
| `update_task_status` | `:update_task_status` | `TaskManager.update_task` |

## Form Handlers in Dashboard

| Event | Handler Module | Entry Point |
|-------|---------------|-------------|
| `send_agent_message` | `DashboardMessagingHandlers` | `Operator.send(sid, content)` |
| `send_team_broadcast` | `DashboardMessagingHandlers` | `Operator.send("team:#{name}", content)` |
| `push_context` | `DashboardMessagingHandlers` | `Operator.send(sid, content, type: :context_push)` |
| `send_targeted_message` | `DashboardTeamInspectorHandlers` | `Operator.send(target, content)` |
| `send_command_message` | `DashboardSwarmHandlers` | `Operator.send(to, content)` |
| `pause_agent` | `DashboardSessionControlHandlers` | `CommandQueue + Mailbox` (direct) |
| `resume_agent` | `DashboardSessionControlHandlers` | `CommandQueue + Mailbox` (direct) |
| `shutdown_agent` | `DashboardSessionControlHandlers` | `CommandQueue + Mailbox` (direct) |

## Unification Opportunities

1. **Route all sends through Gateway** -- EventController's direct Mailbox calls and
   SessionControl's direct CommandQueue calls should use `Gateway.Router.broadcast`
   for consistent audit trail and protocol tracking.

2. **Consolidate form handlers** -- Five different `phx-submit` events all call
   `Operator.send`. Could be one handler with a channel parameter.

3. **Ash-ify the pipeline** -- Mailbox, CommandQueue, and AgentRegistry are plain
   GenServers. Could become Ash resources with `Ash.DataLayer.Simple` (like Fleet/Activity
   domains) for consistent query/action patterns.

4. **Single message resource** -- An `Activity.Message` Ash resource already exists but
   uses a Simple data layer fed by `Mailbox.all_messages`. The Mailbox ETS store could
   be replaced by the Ash resource's own data layer.

5. **Unify PubSub topics** -- `"agent:{sid}"` and `"agent:operator"` serve the same
   purpose. The dashboard subscribes to both separately.
