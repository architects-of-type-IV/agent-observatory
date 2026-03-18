# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents, Kardashev Type IV suite
- **Architect**: the user -- has authority over everything
- **Archon**: the Architect's agent interface, floor manager AI

## The Golden Rule: MES TeamSpawner Pattern (2026-03-18, PROVEN)
Every team MUST follow this exact pattern. No exceptions. No shortcuts.
1. Build agent list upfront with name, capability, prompt
2. `write_agent_scripts(run_id, mode, agents)` -- writes .txt + .sh per agent to `~/.ichor/{mode}-{run_id}/`
3. `create_session_with_agent(session, cwd, run_id, mode, hd(agents))` -- tmux new-session
4. `create_remaining_windows(session, cwd, run_id, mode, tl(agents))` -- tmux new-window per remaining agent
5. `Enum.each(agents, &register_agent(...))` -- BEAM fleet with liveness_poll: true
6. Agents connect to MCP via .mcp.json in cwd (auto-discovered by Claude)

**NEVER** use InstructionOverlay to .claude/ (pollutes all agents).
**NEVER** use dynamic spawning via spawn_agent MCP at runtime.
**NEVER** pass prompts via `-p` flag (shell arg limits).

## Subsystem Architecture (2026-03-18, IMPLEMENTED)
- MES projects are standalone Mix libraries in `subsystems/{name}/`
- Stubs provide compile-time behaviour/struct definitions (4 files)
- SubsystemLoader hot-loads only `Ichor.Subsystems.*` modules into BEAM
- Signals provide full decoupling -- no compile-time dependency on host
- Workers build inside subsystem dir, compile independently
- CompletionHandler (Mes domain) reacts to `:dag_run_completed` -> SubsystemLoader

## Ichor.Dag Domain (2026-03-18, IMPLEMENTED)
- Separate Ash domain from Genesis. Genesis = planning, Dag = execution.
- Resources: Run (SQLite), Job (SQLite) with after_action signal hooks
- Pure modules: Graph (waves, critical path), Validator (cycles, overlaps), WorkerGroups (file-based grouping)
- I/O: Loader (tasks.jsonl + Genesis -> DB), Exporter (DB -> tasks.jsonl write-through)
- Lifecycle: HealthChecker, RunProcess (signal-driven), RunSupervisor, Supervisor
- MCP tools: 7 actions in AgentTools.DagExecution
- Spawner: ALL agents upfront (coordinator + lead + N workers per file group)
- Archon TeamWatchdog: signal-driven lifecycle monitor (no timers)

## Critical Constraints
- **No external SaaS** -- self-hosted only
- **External apps DOWN** -- Memories (4000) and Genesis app (hardware)
- **MES scheduler PAUSED**
- **Module limit**: 200 lines, single responsibility
- **Style**: pattern matching, no if/else, ash-elixir-expert.md mandatory
- **Ash**: code_interface for all actions, relationships via belongs_to/has_many
- **Ash codegen**: snapshots broken, use manual migrations
- **No manual migrations**: all business logic through Ash Domain/Resources

## User Preferences (ENFORCED)
- "Always go for pragmatism"
- "Never think of solutions yourself. LLMs can judge and discuss."
- "Architect solutions with agents before coding"
- "MES teams work perfect. Follow that pattern."
- "Archon is always watching. Signal-driven, not timers."
- "RESPECT ash-elixir-expert.md"
- "Surgical precision. No exploration. Write code, verify, report."
- "Use multiple agents for research and review"
- "/dag skill is absolutely perfect. Our app needs to be as perfect."
