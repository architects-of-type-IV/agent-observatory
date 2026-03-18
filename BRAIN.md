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

## ichor_contracts Architecture (2026-03-18, IMPLEMENTED)
- Facade + behaviour + config dispatch pattern for `Ichor.Signals`
- `ichor_contracts` owns: Signals facade, Behaviour, Noop, Message, Topics, Subsystem, Info
- Host owns: Signals.Runtime (impl), Signals.Domain (Ash), Catalog, Bus, Buffer
- Config: `:ichor_contracts, :signals_impl, Ichor.Signals.Runtime`
- Subsystems depend on `{:ichor_contracts, path: "../ichor_contracts"}` -- never on the host
- No stubs, no naming conflicts -- contracts IS the canonical source of truth
- codex (GPT-5.4) was the architecture sparring partner for this design

## Subsystem Architecture (2026-03-18, IMPLEMENTED)
- MES projects are standalone Mix libraries in `subsystems/{name}/`
- Scaffold creates: mix.exs, README.md, integration.md, placeholder module
- Workers build inside subsystem dir ONLY -- reinterpret host-file tasks
- Signals provide full decoupling -- no compile-time dependency on host
- CompletionHandler (Mes domain) reacts to `:dag_run_completed` -> SubsystemLoader

## Ichor.Dag Domain (2026-03-18, IMPLEMENTED)
- Separate Ash domain from Genesis. Genesis = planning, Dag = execution.
- Resources: Run (SQLite), Job (SQLite) with after_action signal hooks
- Pure modules: Graph, Validator, WorkerGroups
- Spawner delegates to WorkerGroups, scaffolds subsystem before launch
- Archon TeamWatchdog: signal-driven lifecycle monitor (no timers)

## Critical Constraints
- **No external SaaS** -- self-hosted only
- **External apps DOWN** -- Memories (4000) and Genesis app (hardware)
- **Module limit**: 200 lines guide, SRP is the real rule
- **Style**: pattern matching, no if/else, ash-elixir-expert.md mandatory
- **Ash**: code_interface for all actions, Domain is canonical API
- **No manual migrations**: all through Ash Domain/Resources
- **One module per file**: nested modules are illegal
- **credo --strict**: must be clean

## User Preferences (ENFORCED)
- "Always go for pragmatism"
- "Architect solutions with agents before coding"
- "MES teams work perfect. Follow that pattern."
- "RESPECT ash-elixir-expert.md"
- "Use multiple agents for research and review"
- "Take ownership" = fix ALL issues, not just new ones
- "Use codex actively as sparring partner"
- "Nested modules are illegal. One module per file."
