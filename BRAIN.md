# BRAIN -- Session Knowledge

## Refactoring Philosophy (2026-03-22, from architect)
- Refactoring is gardening. Water a little every day. Not massive rewrites.
- Shape to generics until you see mirrors/twins. Then merge.
- Naming is what you do last. Don't invent concepts before the shape is clear.
- You either score or store. Pure functions separate from side effects.
- Signals = PubSub. Emit, subscribe, act. That's it.

## Shape-First Code Review Questions
- Open the file. Behaviours? Specs? Docs? Pipes? Comprehensions?
- Are there functions with the same shape? 10 functions differing by a string param = one generic function.
- Why did we write code? Could this be a pattern match? A guard?
- Can I rearrange arities, rename generically, and find a stdlib function?
- Why is this transformation placed HERE?
- A module is a library. Small, focused, complete API.
- Everything that subscribes to a topic is a monitor/watcher/subscriber. Same concept.

## Entropy Scoring (2026-03-22)
- Raw events have `session_id`, `tool_name`, `hook_event_type` (all atom-keyed).
- `payload["cognition"]["intent"]` is NOT in raw events -- it's a DecisionLog-computed field.
- Score entropy with `{tool_name, hook_event_type}` tuple. No need for intent.
- Score is pure (compute_score/classify). Store is side effect (ETS insert). Keep separate.
- `lookup_session/3` is shared between GenServer.call and signal handle_info paths.

## MCP Inbox (2026-03-22)
- AgentState.prepend_to_inbox MUST populate inbox for ALL agents regardless of backend.
- Tmux delivery (visual) and MCP inbox (programmatic) are independent channels.
- Bounded at 200 entries via Enum.take.

## Prompt Separation
- Workshop = what you are. Infrastructure = where you are.
- Do NOT store runtime context in Workshop. Injected at TeamSpec compile time.

## AD-8: Reliability
- Ash -> Oban -> PubSub. Mandatory reactions through Oban. PubSub for observation only.
- Signal handlers are best-effort/advisory. Loss acceptable.

## GenServer Signal Emission
- `terminate/2` is canonical emission point for lifecycle signals.
- Set status flag before stopping to distinguish completed vs abnormal.

## Centralized Code Interface
- Define action interfaces on the Domain, not the Resource.

## AshSqlite Limitations
- No aggregates. No ALTER COLUMN.
