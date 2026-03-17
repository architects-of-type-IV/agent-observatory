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
- Current MES Project status (proposed/loaded) doesn't capture pipeline position -- design debt
- UI should make current state obvious and next action clear
- Actions should be contextual to current state (can't run Mode B before Gate A passes)

## Genesis Domain (2026-03-16, tasks 140-152 COMPLETE + lifecycle 2026-03-17)
- 10 Ash resources: Node, Adr, Feature, UseCase, Checkpoint, Conversation, Phase, Section, Task, Subtask
- All use proper Ash relationships (belongs_to/has_many), NOT raw UUID attributes
- Hierarchy: Node -> {ADRs, Features, UseCases, Checkpoints, Conversations, Phases -> Sections -> Tasks -> Subtasks}
- 20 MCP tools in 4 modules: GenesisNodes (5), GenesisArtifacts (7), GenesisGates (3), GenesisRoadmap (5)
- MCP tools return plain maps (not Ash structs) for serialization
- Ash codegen has snapshot issues with this project -- manual migrations work reliably
- Pipeline: MES brief -> Mode A (ADRs) -> Mode B (FRDs/UCs) -> Mode C (roadmap) -> DAG
- **Mode dispatch**: ModeSpawner + ModeRunner + ModePrompts (3 agents per mode, tmux sessions)
- **DAG generator**: nested Ash preload, flat traversal, dotted IDs with blocked_by remapping
- **TmuxHelpers**: shared module for tmux/fleet helpers
- **RunProcess**: Genesis.RunProcess monitors teams, auto-kills tmux + disbands fleet on completion
- **Genesis.Supervisor**: DynamicSupervisor for RunProcesses, wired into application.ex

## Mode A Smoke Test Results (2026-03-17)
- Infrastructure works: MCP tools, script generation, tmux, fleet registration all verified
- Coordinator broke protocol: self-synthesized ADRs instead of waiting for architect/reviewer
- Root cause: prompt escape clause "synthesize ADRs yourself"
- Fix: explicit patience rules, "if you break protocol, team will be destroyed"
- Scout --allowedTools was blocking MCP messaging (fixed)
- Genesis teams now auto-cleanup via RunProcess (listens for operator delivery + liveness poll)

## MES UI Redesign (2026-03-17, IN PROGRESS)
- Single unified view -- no separate tabs
- Factory pipeline visualization, not project browser
- Action bar at top (not panel), metadata sidebar right, reader sidebar on artifact click
- Artifact tabs: Decisions, Requirements, Checkpoints, Roadmap
- Cross-references resolved from DB relationships, shown as clickable links
- Read-only -- agent-produced artifacts
- Design needs rewrite with factory state machine framing
- MUST spawn architect agents for design work -- never design alone

## Critical Constraints
- **No external SaaS** -- ADR-001. Self-hosted only.
- **External apps DOWN** -- Memories (port 4000) and Genesis app (hardware issues)
- **MES scheduler PAUSED** -- tmp/mes_paused flag set
- **Module limit**: 200 lines, single responsibility
- **Style**: pattern matching, no if/else/cond
- **Ash relationships**: always use belongs_to/has_many, never raw UUID attributes

## User Preferences (ENFORCED)
- "We dont filter. We fix implementation"
- "BEAM is god"
- "Always go for pragmatism"
- "Never think of solutions yourself. LLMs can judge and discuss."
- "Architect solutions with agents before coding"
- "Our project is an Ash project" -- use Ash patterns properly
- Minimal JS. No emoji. Execute directly.
- MES is an automated factory -- everything should flow through the pipeline
