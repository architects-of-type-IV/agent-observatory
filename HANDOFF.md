# ICHOR IV - Handoff

## Current Status: Codebase Rename Complete (2026-03-09)

### Just Completed

**Codebase Rename: Observatory -> Ichor**
- `Observatory.*` -> `Ichor.*` (211 modules), `ObservatoryWeb.*` -> `IchorWeb.*`
- OTP app: `:observatory` -> `:ichor`
- Dashboard title: "ICHOR IV" (page header, browser tab, root layout)
- `lib/observatory/` -> `lib/ichor/`, `lib/observatory_web/` -> `lib/ichor_web/`
- `~/.observatory/` -> `~/.ichor/` (tmux socket, memory store paths)
- Signal patterns: `ICHOR_DONE`, `ICHOR_BLOCKED`
- HTTP headers: `x-ichor-signature`, `x-ichor-operator-id`
- Session cookie: `_ichor_key`
- DB files: `ichor_dev.db`, `ichor_test.db`
- ETS tables: `:ichor_tool_starts`, `:ichor_notes`
- :pg scope: `:ichor_agents`, group: `:ichor_hosts`
- Assets: localStorage keys `ichor:*`, CSS source path, phoenix-colocated import
- Config: esbuild/tailwind keys, live reload patterns, all `:ichor` refs
- Ash resource snapshots updated (`Ichor.Repo`)
- `.mcp.json`, `.claude/settings.local.json`, `.gitignore` updated
- Project folder remains `observatory/` (unchanged)
- `mix compile --warnings-as-errors` -- CLEAN

### Previously Completed
- Agent lifecycle closed-loop (6 gaps fixed, single cleanup point)
- Full CSS tokenization (1,200+ refs migrated)
- Archon HUD + Chat + Memories integration
- BEAM-native fleet foundation
- DashboardLive dispatch/3 refactor
- Legacy module elimination (Mailbox, CommandQueue, TeamWatcher)

### .env Setup
- `ANTHROPIC_API_KEY` in `.env` at project root
- Not auto-loaded -- `source .env` before `mix phx.server`

### Build Status
`mix compile --warnings-as-errors` -- CLEAN

### Key Architecture Decisions
- **Module prefix**: `Ichor` (not `IchorIV`). Dashboard title is "ICHOR IV".
- **AgentProcess.terminate/2** is the single lifecycle reconciliation point.
- **No theme switcher UI** -- user decided against on-demand theme switching.

### Runtime Notes
- After rename, must restart the BEAM process (old `observatory` app won't match)
- `~/.ichor/tmux/obs.sock` -- tmux socket path (create dir on first run)
- Port 4005

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
