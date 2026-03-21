# Architecture Audit -- 2026-03-21 (revised)

Diagrams: [architecture.md](../diagrams/architecture.md) | Slices: [vertical-slices.md](2026-03-21-vertical-slices.md)

## Session Work Completed

**Ash idiomacy audit**: 16 high findings fixed across 5 domains, 33 resources.
**Code review**: 20 findings fixed (7 critical security/crash, 13 high).
**Module decompositions**: Runner, AgentWatchdog, EventStream, Spawn -> 10 focused helpers.
**PR #1 merged**: AgentProcess decomposed into 6 helpers + inbox semantics fixed.
**Frontend dead code**: 8 files removed, 15+ dead functions cleaned.

---

## DOMAIN BOUNDARIES

Workshop, Factory, and Archon are distinct domains with distinct purposes.

| Domain | Page | Purpose |
|--------|------|---------|
| **Workshop** | `/workshop` | Design and build agents and teams |
| **Factory** | `/mes` | Turn project-briefs into project requirements |
| **Archon** | (system) | The agent that manages the entire app |
| **SignalBus** | `/signals` | Pub/sub reactive backbone |
| **Infrastructure** | (none) | Runtime host layer -- NOT a business domain |
| **Mesh** | (topology) | Observability DAG, ephemeral |

**Planned: Ichor.Discovery** -- expose all Ash actions by Domain for dynamic workflow composition in UI. Actions become pluggable pipeline steps.

### DB1. Archon Contains Unrelated Runtime Modules
TeamWatchdog is generic run lifecycle cleanup. SignalManager is signal routing.
Neither is Archon-specific.

**Proposed**: Keep Manager + Memory in Archon (its tool surface). TeamWatchdog becomes a signal subscriber that enqueues Oban cleanup jobs (see O3). SignalManager moves to SignalBus or is absorbed into EventBridge.

### DB2. Infrastructure Ash Resources Are Misplaced
CronJob, HITLInterventionEvent, and WebhookDelivery are Ash resources on a non-domain.

**Proposed**: CronJob -> Factory. HITLInterventionEvent -> SignalBus. Infrastructure stays as pure host/adapter.

---

## TEAMSPEC: THE HIDDEN CONCEPT

`Workshop.TeamSpec` (395 lines) is flagged as a god module. But the real issue isn't size -- it's that **prompt injection is not Workshop's concern**.

TeamSpec does two things:
1. **Team compilation** -- transform a Workshop design (Team + Presets + CanvasState) into `Infrastructure.TeamSpec`. This IS Workshop's job.
2. **Mode-specific prompt injection** -- knowing MES prompts, pipeline prompts, planning prompts. This is the CALLER's job.

The hidden concept: the **prompt strategy is the caller's responsibility**, not the compiler's.

`build_from_state/2` already accepts `prompt_builder:` and `agent_metadata_builder:` as options -- the architecture is 80% there. The problem: the public API `build(:mes, ...)`, `build(:pipeline, ...)`, `build(:planning, ...)` puts the caller-specific knowledge inside Workshop.

**Proposed**:
- `Workshop.TeamSpec.compile(canvas_state, opts)` -- pure compilation, no mode knowledge
- Each caller provides its own prompt strategy:
  - `Factory.Spawn` provides pipeline/planning prompt builders when calling compile
  - `Factory.MesScheduler` (or Runner) provides MES prompt builders
  - `Workshop.Spawn` provides workshop-specific prompt builders
- The `build(:mes|:pipeline|:planning, ...)` functions move to their respective callers
- Workshop.TeamSpec shrinks to ~150 lines of pure team compilation

---

## SAMENESS / DUPLICATION

### S1. Three Prompt Builders With Identical Protocol
TeamPrompts, PlanningPrompts, PipelinePrompts copy "CRITICAL RULES" + "ANNOUNCE READY" blocks verbatim.

**Proposed**: Extract shared protocol into a module (Workshop.PromptProtocol or similar) with `critical_rules(tool_prefix)`, `roster_block(session, names)`, `announce_ready(session_id)`.

### S2. Watchdogs Call Across Domains Instead of Using Signals
AgentWatchdog and TeamWatchdog both write inbox notifications, call disband_team, react to agent_stopped. They do this via direct cross-domain calls.

**Proposed (revised)**: Don't merge them. Instead:
- Each watchdog emits signals for its decisions
- Cleanup side effects become signal subscribers that enqueue Oban jobs
- Extract `Operator.Inbox` (see A3) so inbox writes go through one module
- The watchdogs stay focused: one watches agents, one watches runs

### S3. Duplicate Spawn + Spec Builder Paths
Workshop.Spawn builds specs independently from Workshop.TeamSpec. Duplicate `slug/1` helper.

**Proposed**: Workshop.Spawn calls `TeamSpec.compile(state, opts)` with a workshop-specific prompt strategy. One compilation path.

### S4. tasks.jsonl Is Cross-Project Interop (NOT duplication)
The app monitors agents across ALL git projects. External projects have their own `tasks.jsonl`. Ash PipelineTask is authoritative for our data. File sync serves interop with external tooling.

**Action**: Keep dual representation. Clarify with comments. Ensure Ash is the write path, file is the sync path.

---

## OBAN JOB CANDIDATES

All align with the Signals-as-backbone pattern: signal -> subscriber -> Oban job -> retry.

### O1. MesScheduler -> Oban Cron Worker
GenServer with Process.send_after every 60s. File-flag pause state.
Replace with Oban cron on `mes` queue. Pause = queue drain. `max_concurrency: 1`.

### O2. CronScheduler -> Oban Cron Entries
GenServer wrapping what Oban does natively. Delete GenServer, move to config.

### O3. TeamWatchdog Cleanup Actions -> Oban Jobs
Archive run, reset tasks, disband team, kill session -- fire-and-forget with no retry.
Each becomes an idempotent Oban worker. TeamWatchdog becomes signal-to-job dispatcher.

### O4. PipelineMonitor Health Check -> Oban Cron
External bash script inside GenServer.call with 15s timeout. Natural Oban job.

### O5. Webhook Delivery Retry -> Oban Worker
Currently fire-and-forget. Needs retry semantics with backoff.

---

## PROCESS ARCHITECTURE

### P1. PipelineMonitor: Eliminate Serializing GenServer
623 lines. Serializes all reads/writes. Derived state recomputable from Ash.
Health check runs bash inside GenServer.call.

**Proposed**: Replace with:
- Pure query module reading from `PipelineTask` Ash resource (no process)
- Oban cron workers for health check + project discovery
- Ash notifier broadcasts when pipeline tasks change (replaces 3s poll)
- LiveView subscribes to signals, calls query module directly

### P2. AgentWatchdog Duplicate Functions
Private functions duplicate the extracted EscalationEngine. Incomplete extraction artifact.

**Action**: Remove private duplicates. Keep only EscalationEngine delegation.

### P3. Signals.Buffer Counter
Sequence counter serializes through GenServer unnecessarily. ETS is public.

**Proposed**: Replace counter with `:atomics`. GenServer stays for subscription only.

---

## MISSING ABSTRACTIONS

### A1. RunSpec Value Object
run_id, kind, session, supervisor spread across 6+ pattern-match trees.

**Proposed**: Struct with `kind, run_id, session, supervisor, registry_key`. Adding a new run kind = one new constructor, not 6 function edits.

### A2. AgentId Value Object
Session IDs are bare strings with encoded information (team, role, run). Parsed by hand in multiple modules. Two field names for same concept (`session_id` vs `agent_id`).

**Proposed**: `%AgentId{kind, session, name, raw}` with `parse/1` and `format/1`.

### A3. Operator.Inbox
Three modules write JSON to `~/.claude/inbox/` with different schemas.

**Proposed**: `Operator.Inbox.write(type, payload)` owns directory, schema, filename convention. Single write path.

---

## WRONG HOMES

### W1. Signals.AgentWatchdog -- not a Signals concern
Fleet health monitoring. Uses signals as input, not as domain. Move to Workshop (it watches workshop agents) or keep in Signals but rename to clarify it's a subscriber, not bus infrastructure.

### W2. Signals.EventBridge -> Mesh.EventBridge
Already supervised by Mesh.Supervisor. Bridges events into CausalDAG. Wrong namespace.

### W3. Signals.EventStream -> Signals.EventStore
Persistence + query module. "Stream" name implies subscription, but it's a store.

### W4. Factory.Floor Mixes Presentation Logic
String-keyed UI maps in domain actions. Should delegate to a View module.

### W5. Archon.MemoriesClient -> Infrastructure.MemoriesClient
Three domains consume it. Shared infrastructure, not Archon-specific.

---

## CROSS-BOUNDARY VIOLATIONS

The fix pattern is always the same: **emit signal, add subscriber**. No direct cross-domain calls.

### X1. Signals <-> Infrastructure Bidirectional Coupling
EventStream calls AgentProcess/FleetSupervisor directly. Infrastructure.Operations calls back into Signals.

**Fix**: EventStream emits `:session_started`, `:session_ended` signals. An Infrastructure subscriber (or Oban job) reacts by creating/terminating AgentProcess. One-way dependency: Infrastructure subscribes to Signals, never the reverse.

### X2. Archon.TeamWatchdog Direct Cross-Domain Calls
Calls Factory.Pipeline, PipelineTask, Spawn, and Infrastructure.FleetSupervisor directly. Writes raw JSON bypassing Bus.

**Fix**: Emit signals (`:run_completed`, `:team_cleanup_needed`). Factory and Infrastructure subscribers react. Inbox writes go through Operator.Inbox.

### X3. TeamSpec Cross-Domain Imports
Imports PlanningPrompts from Factory into Workshop.

**Fix**: See TeamSpec section above. Callers inject their prompt strategies. Workshop.TeamSpec has no Factory imports.

---

## PRIORITY EXECUTION ORDER

Grouped by dependency. Each group can be parallelized internally.

### Wave 1: Small, No Dependencies (parallel)
| # | Finding | What |
|---|---------|------|
| 1 | A3 | Extract `Operator.Inbox` module |
| 2 | P2 | Remove duplicate functions in AgentWatchdog |
| 3 | W2 | Move EventBridge to Mesh namespace |
| 4 | W5 | Move MemoriesClient to Infrastructure |
| 5 | S1 | Extract shared prompt protocol module |

### Wave 2: Oban Migration (parallel, after Wave 1)
| # | Finding | What |
|---|---------|------|
| 6 | O1 | MesScheduler -> Oban cron worker |
| 7 | O2 | CronScheduler -> Oban cron entries |
| 8 | O5 | Webhook delivery -> Oban worker with retry |

### Wave 3: Structural (sequential, after Wave 2)
| # | Finding | What |
|---|---------|------|
| 9 | X1 | Decouple EventStream from Infrastructure via signals |
| 10 | TeamSpec | Refactor to compile(state, opts) -- callers inject prompts |
| 11 | A1+A2 | RunSpec + AgentId value objects |
| 12 | X2+O3 | TeamWatchdog -> signal emitter + Oban cleanup jobs |

### Wave 4: Large Structural (after Wave 3)
| # | Finding | What |
|---|---------|------|
| 13 | P1 | Eliminate PipelineMonitor GenServer |
| 14 | DB2 | Move Infrastructure Ash resources to correct domains |
