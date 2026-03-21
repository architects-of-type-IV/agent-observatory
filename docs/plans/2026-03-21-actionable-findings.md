# Actionable Findings -- 2026-03-21

Architecture-informed code review. Every finding traces back to a principle from [vertical-slices.md](2026-03-21-vertical-slices.md).

Related: [Glossary](GLOSSARY.md) | [Diagrams](../diagrams/architecture.md)

---

## P1: Hardcoded spawn modes (should be data-driven)

Every place that pattern-matches on `:mes | :pipeline | :planning` instead of reading Workshop team config.

| # | File | What | Effort |
|---|------|------|--------|
| 1.1 | `runner.ex:422-437,566-576` | `registry_key/1`, `supervisor_for/1`, `session_for/1`, `build_terminate_payload/1` -- 5 functions x 3 clauses each | medium |
| 1.2 | `team_spec.ex:27-128` | `build/3`, `build/7`, `build/6` -- three separate function heads with mode-specific private internals | large |
| 1.3 | `team_spec.ex:172-181` | `mes_prompt/3` hardcodes 5 agent role names in a case statement | medium |
| 1.4 | `team_spec.ex:296-322` | `planning_prompt_map/5` and `planning_agent_names/1` branch on "a"/"b"/"c" strings | medium |
| 1.5 | `mes_scheduler.ex:54-143` | Hardcodes `:mes` kind, `"mes-"` prefix, `Runner.list_all(:mes)` | medium |

**Root cause**: TeamSpec.build/N is the compiler that all Factory spawns go through. It encodes mode-specific knowledge (which agents, which prompts, which prompt module) that should come from Workshop data.

**The gap** (from spawn readiness review): Workshop team/agent slots have no binding to their prompt content. `persona` field exists but carries only short blurbs. Full prompts are in TeamPrompts/PipelinePrompts/PlanningPrompts as code.

**Two paths forward**:
- **Option A** (prompt_module per team): Team record carries a `prompt_module` atom. TeamSpec.compile reads it, calls `prompt_module.build_prompt(agent, context)`. Medium effort.
- **Option B** (prompt_template per slot): AgentSlot carries template strings with `{{run_id}}` placeholders. Large effort (migration + template editor UI).

**Option A is lower risk.** Prompt modules stay as versioned, testable code. The binding moves from hardcoded inside TeamSpec to declared on the Team record.

---

## P2: Direct cross-domain calls (should emit signals)

| # | File | From -> To | Side effect? | Effort |
|---|------|-----------|-------------|--------|
| 2.1 | `agent_watchdog.ex:256,306` | Signals -> Infrastructure | HITLRelay.pause/unpause (mutation) | medium |
| 2.2 | `agent_watchdog.ex:163-180` | Signals -> Factory | Board.list_tasks + Board.update_task (mutation) | small |
| 2.3 | `event_bridge.ex:77,289` | Signals -> Phoenix.PubSub | Direct subscribe/unsubscribe bypassing Ichor.Signals | small |

**2.2 is the easiest win**: AgentWatchdog already emits `:agent_crashed` at line 152. The `reassign_agent_tasks` logic just needs to move into a Factory subscriber that reacts to `:agent_crashed`. One move, zero new signals needed.

**2.1 is the most impactful**: Decoupling escalation decisions from infrastructure mutations. The watchdog decides "escalate to level 2", emits a signal. An infrastructure subscriber calls HITLRelay.pause.

**2.3 is cleanup**: EventBridge should use `Ichor.Signals.subscribe/unsubscribe` instead of raw Phoenix.PubSub calls.

---

## P3: Discovery readiness (actions need descriptions + typed returns)

| # | File | Issue | Effort |
|---|------|-------|--------|
| 3.1 | `workshop/team.ex:70-97` | 7 actions with no descriptions. spawn_team is critical for Discovery | small |
| 3.2 | `workshop/agent.ex:140-370` | 4 overlapping spawn actions returning opaque :map. Not composable | medium |
| 3.3 | `factory/floor.ex:10-164` | 5 actions return :map with no shape documentation | small |
| 3.4 | `signals/operations.ex:35-66` | Arguments lack descriptions. acknowledge_message is a stub | small |

**3.2 is the design question**: Four ways to spawn an agent (`:spawn`, `:launch`, `:spawn_agent`, `:spawn_archon_agent`). Discovery can't distinguish them. Consolidate to two: programmatic fleet spawn vs human-initiated launch.

**3.1, 3.3, 3.4 are mechanical**: Add `description` strings to actions and arguments. One pass, many files.

---

## Prompt Duplication (from spawn readiness review)

The CRITICAL RULES block appears **verbatim in 11+ prompt functions** across three modules:
- `workshop/team_prompts.ex` (MES)
- `workshop/pipeline_prompts.ex` (pipeline)
- `factory/planning_prompts.ex` (planning)

This is the protocol text about `send_message`/`check_inbox` communication rules. When the protocol changes, three files must be updated. The `planning_prompts.ex` module lives in Factory but has zero Factory-specific content -- it should be in Workshop.

**Fix**: Extract shared protocol blocks into a single module. Move `planning_prompts.ex` to Workshop.

---

## Workshop.Spawn vs Factory.Spawn (from spawn readiness review)

Two parallel spawn implementations with zero convergence:

| | Workshop.Spawn | Factory.Spawn |
|---|---|---|
| Entry point | `spawn_team(name)` | `spawn(:pipeline\|:planning, ...)` |
| Spec builder | Inline `build_spec` + `build_preset_spec` | `TeamSpec.build/N` |
| Prompt source | `persona` field from Workshop data | TeamPrompts/PipelinePrompts/PlanningPrompts |
| Session naming | `"workshop-SLUG"` | `"mes-ID"` / `"pipeline-ID"` / `"planning-MODE-ID"` |
| Launch method | Signal round-trip via TeamSpawnHandler | Direct `TeamLaunch.launch` call |
| Lifecycle | No Runner (fire-and-forget) | Runner.start with monitoring |
| Pre-spawn steps | None | Pipeline: scaffold + compile + validate + group |

**The convergence point is TeamSpec.compile**: both paths should call it. Workshop.Spawn's `build_spec` should delegate to TeamSpec instead of duplicating the compilation logic.

**Pipeline pre-spawn steps are legitimate** -- loading tasks, validating DAGs, grouping workers. These aren't spawn concerns; they're Factory concerns that happen before spawn. A generic spawn/1 doesn't eliminate them; it just means Factory does its prep work and then calls `spawn("pipeline")` with context.

---

## Priority Order

### Wave 1: Descriptions + cleanup (small, parallel)
- Add `description` to all Workshop, Factory, SignalBus, Infrastructure Ash actions
- Add `description` to all action arguments
- Move `planning_prompts.ex` to Workshop namespace
- Extract shared CRITICAL RULES into protocol module
- Fix EventBridge raw PubSub calls

### Wave 2: Signal decoupling (medium, parallel)
- Move `reassign_agent_tasks` from AgentWatchdog to Factory subscriber on `:agent_crashed`
- Decouple AgentWatchdog escalation from HITLRelay direct calls

### Wave 3: Spawn convergence (large, sequential)
- Add `prompt_module` field to Team/Preset config
- Refactor TeamSpec.build/N into TeamSpec.compile(state, opts)
- Workshop.Spawn delegates to TeamSpec.compile
- Runner mode config becomes data fields, not pattern-match dispatch
- Consolidate Agent's 4 spawn actions into 2

### Wave 4: MesScheduler as Oban cron (medium, after Wave 3)
- Replace GenServer timer with Oban cron worker
- Pause/resume via Oban queue drain
- Generic enough to parameterize for other team types
