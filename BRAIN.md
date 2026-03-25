# BRAIN -- Session Knowledge

## Refactoring Philosophy (from architect)
- Refactoring is gardening. Water a little every day.
- Shape to generics until you see mirrors/twins. Then merge.
- Naming is what you do last.
- You either score or store. Pure functions separate from side effects.
- Signals = PubSub. Emit, subscribe, act.
- A module is a library. Small, focused, complete API.
- Everything that subscribes is a monitor/watcher/subscriber. Same concept.

## Shape-First Review
- Open file. Behaviours? Specs? Docs? Pipes? Comprehensions?
- 10 functions differing by a string param = one generic function.
- Can I rearrange arities and find a stdlib function?
- Why is this transformation placed HERE?
- Dispatch params first, unused params last or removed.

## Entropy Scoring
- Raw events: session_id, tool_name, hook_event_type (atom-keyed).
- Score with {tool_name, hook_event_type} tuple.
- classify/3 is pure. emit_state_change/4 is side effect. Separate.

## MCP Inbox
- prepend_to_inbox MUST populate for ALL agents (tmux + MCP are independent channels).
- Bounded at 200 entries.

## Prompt Separation
- Workshop = what you are. Infrastructure = where you are.

## AD-8: Reliability
- Ash -> Oban -> PubSub. Mandatory through Oban. PubSub for observation.
- Signal handlers are best-effort/advisory.

## GenServer Patterns
- terminate/2 is canonical emission point for lifecycle signals.
- Task.start for fire-and-forget calls that may fail (e.g. HITLRelay.unpause).
- Don't use try/catch/rescue for GenServer calls to other processes.

## Centralized Code Interface
- Define action interfaces on the Domain, not the Resource.

## AshSqlite (historical -- now on PostgreSQL)
- Migrated to PostgreSQL. SQLite limitations no longer apply.

## Dead Code Hunting Pattern
- For each directory under lib/, check if modules inside are referenced from OUTSIDE that dir.
- For each supervised process, trace whether its public API is called from anywhere.
- PubSub: check broadcast topics have subscribers, and vice versa.
- String references in templates (PluginScaffold) don't count as real callers.
- Mesh subsystem was ~1000 lines with zero external consumers. Found by tracing Ichor.Mesh.* references outside lib/ichor/mesh/.

## Signals Architecture (ADR-026 in progress)
- Old PubSub system still running (Signals.emit -> Runtime -> PubSub broadcast).
- New GenStage pipeline running alongside: Event -> Ingress -> Router -> SignalProcess -> Handler.
- `use Ichor.Signal` macro for declarative signal creation.
- EventStream bridges hook events into both systems (old PubSub + new Ingress).
- FromAsh notifier is a stub -- Wave 3 replaces it with real %Event{} emission.
- Naming rule: big to small, dot-delimited. agent.tool.budget.exhausted.
- Event = something happened. Signal = enough happened. Handler = now act.
- Signal modules: Agent.ToolBudget (budget enforcement), Agent.MessageProtocol (comm rules).
- SignalProcess: one GenServer per {module, key}, DynamicSupervisor + Registry, idle shutdown.

## Audit Pipeline Lessons
- 6 parallel agents can step on each other -- syntax errors from map keyword mixing.
- Verify agents must check ALL findings, not spot-check.
- Agents need explicit "add specs and docs" instructions -- they don't do it by default.
