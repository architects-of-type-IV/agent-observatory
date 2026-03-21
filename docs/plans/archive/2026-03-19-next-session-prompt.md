# Next Session Starter Prompt (codex-generated 2026-03-19)

Read HANDOFF.md, BRAIN.md, and progress.txt for full context.

Last session: Massive refactoring. 10→4 Ash Domains (Control, Projects, Observability, Tools). 3 Ecto→Ash conversions. ~22 modules inlined. Signal livefeed refactored to LiveView streams. 4 GenServers merged into AgentWatchdog. 13 Ash.Type.Enums. Tool Profiles created. Doc/spec sweep completed.

**PRIMARY TASK: Physical File Reorganization**

Module namespaces still reflect old domains but domain: declarations point to new ones. The file structure needs to match:

- `lib/ichor/fleet/*.ex` → `lib/ichor/control/`
- `lib/ichor/workshop/*.ex` → `lib/ichor/control/`
- `lib/ichor/genesis/*.ex` → `lib/ichor/projects/`
- `lib/ichor/mes/*.ex` → `lib/ichor/projects/`
- `lib/ichor/dag/*.ex` → `lib/ichor/projects/`
- `lib/ichor/events/*.ex` → `lib/ichor/observability/`
- `lib/ichor/activity/*.ex` → `lib/ichor/observability/`
- `lib/ichor/agent_tools/*.ex` → `lib/ichor/tools/`

This means renaming ~150 defmodule names AND updating every reference. Do in safe batches by domain, lowest risk first.

**Batch order:**
1. events/activity → observability (lowest blast radius)
2. agent_tools → tools
3. fleet/workshop → control
4. genesis/mes/dag → projects
5. Global reference repair + compile/test

**After file reorg:**
- RunProcess lifecycle consolidation (3 parallel implementations)
- Component library (variant-based primitives)
- Server restart + MES team relaunch

**Constraints:** ash-elixir-expert agents only. Consult codex before each move. No backward compat. Surgical. Frontend must work. Build clean at every commit. Split work evenly. DecisionLog stays Ecto.

**Read first:** HANDOFF.md, BRAIN.md, control.ex, projects.ex, observability.ex, tools.ex, application.ex, system_supervisor.ex, router.ex
