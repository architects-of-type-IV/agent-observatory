# ICHOR IV - Handoff

## Current Status: SETTINGS + SAFETY FIXES (2026-03-22)

~46 commits. Settings domain added. 5 safety/cleanup findings resolved. Build clean.

### Latest: Settings Page + Safety Fixes

#### Settings Domain (new)
- `Ichor.Settings` domain with `SettingsProject` resource (AshSqlite, table: `settings_projects`)
- Embedded `Location` resource (local/remote) with `LocationType` and `AuthMethodType` Ash enums
- `GitInfo` change auto-detects `repo_name`/`repo_url` from `.git` folder on create/update
- 6th nav view at `/settings/projects`, gear icon in bottom nav
- Phoenix Forms with `inputs_for` for embedded Location
- Server-side folder browser (Elixir `File.ls` -- browser can't expose paths)
- Category sidebar: Projects active, 4 stubbed (Operational, Integrations, UI Preferences, Feature Flags)

#### Safety Fixes (all 5 complete)
- **ANTI-5**: Blocking I/O removed from AgentProcess, OutputCapture, MemoriesBridge -- Task.Supervisor
- **SF-7**: EventStream ETS `:public` -> `:protected`, writes through GenServer
- **SF-8**: `:run_complete` single emission from `terminate/2`, pipeline completion idempotent
- **DB-1**: 20 orphaned tables dropped (migration with FK-ordered drops)
- **DB-2**: 17 stale snapshots removed, 10 remaining match active resources

#### Pre-existing Bug Fixes
- `pipeline_state` crash: signal merges into existing state
- `Map.get` defaults for `.total`/`.blocked` in header
- AgentProcess `terminate(:tmux_gone)` unreachable -- fixed stop reason

### Build
- `mix compile --warnings-as-errors`: CLEAN
- `mix ash.migrate`: CLEAN

### Remaining (tracked in tasks.jsonl)
**UI:**
- UI-WS-PROMPTS: Add prompt CRUD to workshop
- Settings: implement remaining categories
- Settings: integrate project list as cwd dropdown in spawn flows

**Features:**
- PulseMonitor (tasks 1.x-4.x)
- Swarm Memory (tasks 72-77)

### Protocols
- Architecture docs authoritative (CLAUDE.md)
- Agents invoke ash-thinking before Ash work
- Use `inputs_for` for embedded Ash resources in Phoenix Forms
- `terminate/2` is the canonical signal emission point for GenServer lifecycle events
- Codex in codex-spar tmux (resume --last if exits)
