# BRAIN -- Session Knowledge

## Prompt Separation (key insight from architect)
- Workshop stores: persona + instructions (what the agent should do)
- Infrastructure injects at launch: team name, session ID, member roster, tmux targets, comm protocol
- Workshop = what you are. Infrastructure = where you are.
- Do NOT store runtime context (session, roster, team members) in Workshop. That's injected dynamically at TeamSpec.compile time.

## AD-8: Reliability Boundary
Ash -> Oban -> PubSub. Mandatory reactions insert Oban jobs directly from notifiers. PubSub for observation only. Reconciler catches crash-window failures.

## spawn/1 Is Generic
team name -> compile Workshop design -> launch. Constraints are pattern matches in subscribers. Don't name what Elixir already has.

## AshSqlite Limitations
No aggregates. No ALTER COLUMN. Enforce at Ash level, remove from migrations.

## Every Oban Worker Must Be Idempotent
Crash windows mean duplicate execution. Design for re-execution tolerance.
