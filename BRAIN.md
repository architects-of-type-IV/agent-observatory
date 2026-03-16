# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface. NOT a rename of Operator.

## MES Factory Model (Factorio, 2026-03-16)
- **Core metaphor**: processes building processes
- **Signal bus** = COMMUNICATION bus (not conveyor belt). Broadcast medium.
- **Subsystem** = assembler (single pipe fitting, one GenServer, <200 lines)
- **Facility** = city block (self-contained composition with standardized signal I/O)
- **Facility teams DEFERRED** -- need 3-5 loaded subsystems + signal catalog first

## Genesis Domain (2026-03-16, tasks 140-152 COMPLETE)
- 10 Ash resources: Node, Adr, Feature, UseCase, Checkpoint, Conversation, Phase, Section, Task, Subtask
- All use proper Ash relationships (belongs_to/has_many), NOT raw UUID attributes
- Hierarchy: Node -> {ADRs, Features, UseCases, Checkpoints, Conversations, Phases -> Sections -> Tasks -> Subtasks}
- 20 MCP tools in 4 modules: GenesisNodes (5), GenesisArtifacts (7), GenesisGates (3), GenesisRoadmap (5)
- MCP tools return plain maps (not Ash structs) for serialization
- Ash codegen has snapshot issues with this project -- manual migrations work reliably
- Pipeline: MES brief -> Mode A (ADRs) -> Mode B (FRDs/UCs) -> Mode C (roadmap) -> DAG
- **UI**: Genesis panel in MES detail, gate check, Mode A/B/C buttons
- **Mode dispatch**: ModeSpawner + ModeRunner + ModePrompts (3 agents per mode, tmux sessions)
- **DAG generator**: nested Ash preload, flat traversal, dotted IDs with blocked_by remapping
- **TmuxHelpers**: shared module for tmux/fleet helpers (used by ModeRunner, available for TeamSpawner/AgentSpawner)

## Critical Constraints
- **No external SaaS** -- ADR-001. Self-hosted only.
- **External apps DOWN** -- Memories (port 4000) and Genesis app (hardware issues)
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
