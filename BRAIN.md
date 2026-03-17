# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, Kardashev Type IV suite
- **Architect**: the user -- has authority over everything. Reviews, decides, advances the pipeline.
- **Archon**: the Architect's agent interface. NOT a rename of Operator.

## MES Factory Model (Factorio, 2026-03-16)
- **Core metaphor**: processes building processes
- **Signal bus** = COMMUNICATION bus (not conveyor belt). Broadcast medium.
- **Subsystem** = assembler (single pipe fitting, one GenServer, <200 lines)
- **Facility** = city block (self-contained composition with standardized signal I/O)
- **Facility teams DEFERRED** -- need 3-5 loaded subsystems + signal catalog first

## Factory State Machine (2026-03-17)
- MES is an automated factory -- one continuous pipeline from ideation to running code
- Each project is a product moving through the line
- Pipeline: Ideation -> Mode A (ADRs) -> Gate A -> Mode B (FRDs/UCs) -> Gate B -> Mode C (Roadmap) -> Gate C -> DAG -> Waves -> Compilation -> Running
- Pipeline stage DERIVED from artifacts, not stored (PipelineStage.derive/1)
- UI makes current state obvious and next action clear via station buttons

## Genesis Domain (2026-03-16, tasks 140-152 COMPLETE + lifecycle 2026-03-17)
- 10 Ash resources: Node, Adr, Feature, UseCase, Checkpoint, Conversation, Phase, Section, Task, Subtask
- All use proper Ash relationships (belongs_to/has_many), NOT raw UUID attributes
- Hierarchy: Node -> {ADRs, Features, UseCases, Checkpoints, Conversations, Phases -> Sections -> Tasks -> Subtasks}
- 20 MCP tools in 4 modules: GenesisNodes (5), GenesisArtifacts (7), GenesisGates (3), GenesisRoadmap (5)
- MCP tools emit genesis_artifact_created signal on create (drives live UI updates)
- Pipeline: MES brief -> Mode A (ADRs) -> Mode B (FRDs/UCs) -> Mode C (roadmap) -> DAG
- **Mode dispatch**: ModeSpawner + ModeRunner + ModePrompts (3 agents per mode, tmux sessions)
- **DAG generator**: nested Ash preload, flat traversal, dotted IDs with blocked_by remapping, /dag-compatible output (priority, acceptance_criteria, ISO 8601 timestamps, notes, roadmap_ref)
- **TmuxHelpers**: shared module for tmux/fleet helpers
- **RunProcess**: Genesis.RunProcess monitors teams, auto-kills tmux + disbands fleet on completion
- **Genesis.Supervisor**: DynamicSupervisor for RunProcesses, wired into application.ex

## Ichor.Dag Domain (2026-03-18, PLANNED -- 19 tasks, IDs 200-218)
- Sovereign DAG execution domain -- replaces /dag CLI skill + SwarmMonitor logic
- **SQLite is runtime truth**, tasks.jsonl syncs via write-through (serialized through RunProcess)
- Two Ash resources: Dag.Run (execution session), Dag.Job (claimable work unit)
- Pure functions: Graph (waves, critical path -- from SwarmMonitor), Validator (cycles, overlaps -- from phase-to-dag)
- I/O: Loader (tasks.jsonl + Genesis -> DB), Exporter (DB -> tasks.jsonl + write-through)
- Lifecycle: HealthChecker (pure Elixir, replaces health-check.sh), RunProcess, RunSupervisor
- MCP tools: 7 actions in AgentTools.DagExecution (next_jobs, claim_job, complete_job, fail_job, get_run_status, load_jsonl, export_jsonl)
- PipelineStage :building derived from active Dag.Run (NOT from Genesis Checkpoint -- clean domain boundary)
- Job.claim re-checks blocked_by transactionally; Job.available uses two-query prepare (SQLite JSON limitation)
- Naming: Job (not WorkItem), external_id (not item_id), allowed_files, phase_label, :reset (not heal), tmux_session, :imported (not :external)
- Agent prompt: SPECS/dag/AGENT_PROMPT.md -- shape-first, boundary-aware Elixir+Ash expert

## Signal System (2026-03-17)
- Auto-derive: unknown signals infer category from name prefix (no manual catalog entry needed)
- Subscribe no longer raises on unknown signals
- Ash.read(filter:) is INVALID in this Ash version -- use code_interface read actions with filter expressions
- New :dag category signals planned (8 signals, must be explicit in catalog, not derived)

## Critical Constraints
- **No external SaaS** -- ADR-001. Self-hosted only.
- **External apps DOWN** -- Memories (port 4000) and Genesis app (hardware issues)
- **MES scheduler PAUSED** -- tmp/mes_paused flag set
- **Module limit**: 200 lines, single responsibility
- **Style**: pattern matching, no if/else/cond, case on true/false OK
- **Ash relationships**: always use belongs_to/has_many, never raw UUID attributes
- **Ash queries**: use code_interface actions, NOT Ash.read with filter option
- **Ash codegen**: snapshots broken, use manual migrations
- **Components**: use defdelegate, promote reusability

## User Preferences (ENFORCED)
- "We dont filter. We fix implementation"
- "BEAM is god"
- "Always go for pragmatism"
- "Never think of solutions yourself. LLMs can judge and discuss."
- "Architect solutions with agents before coding"
- "Our project is an Ash project" -- use Ash patterns properly
- Minimal JS. No emoji. Execute directly.
- MES is an automated factory -- everything should flow through the pipeline
- Components should use defdelegate and promote reusability
- "The /dag skill is absolutely perfect. Our app needs to be as perfect."
- Use multiple agents for research and review -- less hallucination, more attention to detail
- Function shape matters -- generic names are good when module + arity + pattern make intent clear
