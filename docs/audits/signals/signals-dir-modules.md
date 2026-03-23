# Signals Directory Modules

## Inside lib/ichor/signals/ -- modules that own concepts

| Module | Concept it claims | GenServer? | Lines |
|--------|------------------|------------|-------|
| `Signals` (facade) | Ash Domain + emit/subscribe API | No | 56 |
| `Signals.Runtime` | PubSub transport | No | 108 |
| `Signals.Behaviour` | Contract definition | No | 12 |
| `Signals.Catalog` | Signal name registry | No | ~50 (aggregator) |
| `Signals.Topics` | Topic string builders | No | 16 |
| `Signals.Message` | Envelope struct | No | 58 |
| `Signals.Noop` | Test impl | No | 31 |
| `Signals.Buffer` | 200-entry signal feed for UI | GenServer | 58 |
| `Signals.Bus` | Message delivery (agent/team/fleet addressing) | GenServer | 195 |
| `Signals.EventStream` | Event buffer, heartbeat, tool interception | GenServer | 427 |
| `Signals.EventStream.Normalizer` | Raw event normalization | No | 115 |
| `Signals.EventStream.AgentLifecycle` | Lifecycle signal emission from events | No | 102 |
| `Signals.EntropyTracker` | Loop detection (sliding window) | GenServer | 190 |
| `Signals.AgentWatchdog` | Team task monitoring, orphan detection | GenServer | 458 |
| `Signals.AgentWatchdog.EscalationEngine` | Nudge escalation state machine | No | 103 |
| `Signals.AgentWatchdog.PaneScanner` | Tmux pane output parsing | No | 83 |
| `Signals.ProtocolTracker` | Inter-agent message tracing | GenServer | 174 |
| `Signals.SchemaInterceptor` | Event validation | No | 55 |
| `Signals.FromAsh` | Ash notifier -> signal bridge | No | 153 |
| `Signals.Operations` | Ash resource: mailbox/inbox actions | No | 169 |
| `Signals.Event` | Ash resource: recent signals | No | 105 |
| `Signals.TaskProjection` | Ash resource: task status projection | No | 36 |
| `Signals.ToolFailure` | Ash resource: tool failure log | No | 60 |
| `Signals.HITLInterventionEvent` | Ash resource: HITL audit log | No | 85 |
| `Signals.TraceEvent` | Struct (unused by ProtocolTracker) | No | 30 |
