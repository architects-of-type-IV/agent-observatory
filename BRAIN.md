# BRAIN -- Session Knowledge

## AD-8: Reliability Boundary (from codex sparring)
Ash -> Oban -> PubSub. Three layers:
- Mandatory reactions: Oban.insert directly from Ash notifier/action body. No PubSub hop.
- Observational: PubSub signal -> UI/logs/topology. Loss acceptable.
- Reconciler: Oban cron checks Ash state for orphaned intents.
If something must happen, persist intent durably first. If merely interesting, publish a signal.

## spawn/1 Is Generic
team name -> compile Workshop design -> launch. Current :mes/:pipeline/:planning are team configs, not code branches. Constraints are pattern matches in subscribers.

## Signals Are Observational, Not Commands
All signals say "this happened." Subscribers decide to act. For mandatory reactions, the durable intent (Oban job) is inserted directly, not through a volatile PubSub hop.

## Don't Name What Elixir Already Has
Pattern matching in a subscriber IS the constraint mechanism. No SpawnPolicy module. Concepts exist in conversation, not as modules.

## AshSqlite Limitations
No aggregates. No ALTER COLUMN. Enforce at Ash level, remove from migrations.

## Prompt Strategy Injection
prompt_module per Team record. Boot-time + changeset validation that module exists and implements behaviour. Compile-time alone is not enough for persisted bindings.

## Every Oban Worker Must Be Idempotent
Mandatory reactions go through Oban. Crash windows mean duplicate execution is possible. Design every worker to tolerate re-execution.
