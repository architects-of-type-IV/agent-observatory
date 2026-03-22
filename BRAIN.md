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

## GenServer Signal Emission Pattern (2026-03-22)
`terminate/2` is the canonical single emission point for lifecycle signals (`:run_complete`).
Never emit completion signals from within the GenServer callback chain -- OTP guarantees
`terminate/2` fires after `{:stop, reason}`, so it covers both happy path and crash-during-cleanup.
Set a status flag in state before stopping to distinguish completed vs abnormal exits.

## AshPhoenix Embedded Resources in Forms (2026-03-22)
- Use `inputs_for` with `field={@form[:embedded_field]}` -- handles both new and existing records
- For new forms: call `AshPhoenix.Form.add_form(form, [:field_name])` to seed the nested form
- Don't use `Phoenix.HTML.Form.input_value` for embedded fields -- returns nested Form structs, not maps
- Browser file pickers can't return filesystem paths (security). Use server-side `File.ls` for folder browsing.

## Centralized Code Interface Pattern (2026-03-22)
Define action interfaces on the Domain, not the Resource. Resource keeps simple names (:create, :read),
Domain adds the prefix: `define :create_settings_project, resource: SettingsProject, action: :create`.

## MCP Inbox Delivery (2026-03-22 bug fix)
AgentState.maybe_inbox MUST populate inbox for ALL agents regardless of backend. Tmux delivery
(async_deliver) and MCP inbox (check_inbox/pop_inbox) are independent channels -- tmux injects
text into the pane (visual), inbox is the programmatic polling channel agents use to coordinate.
Commit 60dae93 broke this by guarding on `backend: nil`. Fix: unconditional prepend + cap at 200.

## Signal Handler Behaviour Pattern (2026-03-22 design)
Instead of creating a new GenServer subscriber for each reactive concern, define a Handler behaviour.
Signals register handler modules in their catalog entry. The Signals facade dispatches to the handler
at emit-time (after PubSub broadcast). Handlers must spawn async for long-running work (LLM calls).
This replaces: subscribe -> handle_info pattern match -> dispatch.

## Signals Domain Boundary Rules (2026-03-22 audit)
The signals/ directory should contain ONLY signal infrastructure: facade, runtime, catalog, topics,
message, handler, buffer, from_ash (notifier adapter). Everything else that USES signals but is not
ABOUT signals belongs elsewhere. Key misplacements found: AgentWatchdog (6 cross-domain imports),
SchemaInterceptor (Mesh concern), ProtocolTracker (monitoring), EntropyTracker (Gateway/Mesh concern),
HITLInterventionEvent (HITL domain), TaskProjection/ToolFailure (Workshop/monitoring).
