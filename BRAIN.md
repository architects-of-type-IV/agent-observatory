# BRAIN -- Session Knowledge

## Prompt Separation (key insight from architect)
- Workshop stores: persona + instructions (what the agent should do)
- Infrastructure injects at launch: team name, session ID, member roster, tmux targets, comm protocol
- Workshop = what you are. Infrastructure = where you are.
- Do NOT store runtime context (session, roster, team members) in Workshop. That's injected dynamically at TeamSpec.compile time.

## AD-8: Reliability Boundary
Ash -> Oban -> PubSub. Mandatory reactions insert Oban jobs directly from notifiers OR directly in the process that detected the need. NEVER PubSub -> subscriber -> Oban.insert (volatile hop). PubSub for observation only. Reconciler catches crash-window failures.

## AD-8 Volatile Hop -- Resolved
Initial approach: GenServer -> Oban.insert directly. Codex flagged as X2 violation (cross-domain import).
Final approach: Supervised domain-local dispatchers (GenServer subscribers under supervision tree). Negligible crash window because they restart immediately. Both AD-8 durability and X2 boundary satisfied.

## Cross-Domain Dependency Injection (Wave 3-4 lesson)
When module A needs data from domain B, pass data as a parameter -- don't import B.
Example: TeamPrompts needed ResearchContext (Factory). Fix: Runner pre-fetches context, passes via opts.
Pattern: caller in owning domain fetches, callee receives as param.

## spawn/1 Is Generic
team name -> compile Workshop design -> launch. Constraints are pattern matches in subscribers. Don't name what Elixir already has.

## AshSqlite Limitations
No aggregates. No ALTER COLUMN. Enforce at Ash level, remove from migrations.

## Every Oban Worker Must Be Idempotent
Crash windows mean duplicate execution. Design for re-execution tolerance.

## Oban Migration Pattern (Wave 2)
When converting GenServer to Oban:
1. Extract the work into an Oban.Worker (perform/1)
2. Keep the public API as a plain module (no GenServer, no state)
3. Remove from supervisor children
4. For cron: use Oban.Plugins.Cron in config.exs
5. For one-shot: caller inserts job via Worker.new/1 |> Oban.insert()
6. For recovery: call recover on startup (Task.start in application.ex)
7. WebhookDelivery pattern: Ash resource tracks delivery state, Oban worker handles retry
