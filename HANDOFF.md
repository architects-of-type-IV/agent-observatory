# ICHOR IV - Handoff

## Current Status: Credo Strict Cleanup IN PROGRESS (2026-03-10)

### Task
Fix ALL `mix credo --strict` issues. Started with ~200, now at 173 remaining.

### Completed (27 issues fixed, clean build)
- **C1+C2: ModuleDoc (14)** -- added `@moduledoc false` to 14 modules (domain, event, web component files)
- **C24: Misc mechanical (13)** -- ParenthesesOnZeroArityDefs, PredicateFunctionNames (+ heex callers), CondStatements (5), NegatedConditionsWithElse, PreferImplicitTry (2), Apply, ExpensiveEmptyEnumCheck

### Remaining (173 issues)
- **AliasUsage: 99 issues** across ~46 files (C3-C12)
- **Nesting: 40 issues** across ~25 files (C13-C17)
- **CyclomaticComplexity: 34 issues** across ~25 files (C18-C23)

### Approach
- **Direct manual fixes ONLY** -- no spawned workers (workers failed 3 times, user lost trust)
- AliasUsage: add `alias` at module top, use short names. Watch for conflicts (two modules sharing last segment).
- Nesting: extract inner logic into `defp` helpers INSIDE same module. Max depth 2.
- CyclomaticComplexity: break complex functions into smaller `defp` functions.
- After each file: `mix compile --warnings-as-errors` to verify.

### Key Lessons from Previous Session
- Sonnet workers cannot reliably refactor Elixir -- they break module dependency graphs
- Multi-line `use Ash.Resource,` statements: `@moduledoc false` goes BEFORE the `use` line
- PredicateFunctionNames: must update ALL callers including .heex templates
- Format-on-save race: Edit tool can fail when hooks modify file between Read and Edit

### After Credo
- Migrate `Ichor.Signal` to `Ichor.Signals` convention per `signals.md`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN (0 warnings)

### Runtime
- Port 4005, `~/.ichor/tmux/obs.sock`
- Memories server on port 4000 (for Archon memory tools)
