# ICHOR IV - Handoff

## Current Status: Credo Strict Cleanup IN PROGRESS (2026-03-11)

### Task
Fix ALL `mix credo --strict` issues. Started with ~200, now at 74 remaining.

### Completed
- **ModuleDoc (14)** -- `@moduledoc false` to 14 modules
- **Misc mechanical (13)** -- CondStatements, PreferImplicitTry, Apply, etc.
- **AliasUsage (99->0)** -- all alias issues fixed across ~45 files
- **AliasOrder (3->0)** -- alphabetized alias declarations

### Remaining (74 issues)
- **Nesting: 40 issues** across 23 files -- extract inner logic into `defp` helpers (max depth 2)
  - Biggest: swarm_monitor.ex (10), memory_store.ex (5), load_teams.ex (2), tmux_discovery.ex (2)
- **CyclomaticComplexity: 34 issues** across ~25 files -- break complex functions

### Approach
- **Direct manual fixes ONLY** -- no spawned workers
- Nesting: extract inner logic into `defp` helpers INSIDE same module. Max depth 2.
- CyclomaticComplexity: break complex functions into smaller `defp` functions.
- After each batch: `mix compile --warnings-as-errors` to verify.

### Key Lessons
- `replace_all: true` corrupts alias declarations -- must manually fix `alias ShortName` back to `alias Full.Path.ShortName`
- Sonnet workers cannot reliably refactor Elixir module dependency graphs
- Multi-line `use Ash.Resource,` statements: `@moduledoc false` goes BEFORE the `use` line

### After Credo
- Migrate `Ichor.Signal` to `Ichor.Signals` convention per `signals.md`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN (0 warnings)
