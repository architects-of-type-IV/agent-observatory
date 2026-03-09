# ICHOR IV (formerly Observatory) - Handoff

## Current Status: AgentRegistry Decomposition + Idiomatic Elixir (2026-03-09)

### Just Completed

**AgentRegistry decomposition into focused submodules:**

AgentRegistry was 669 lines doing 5 things. Now decomposed into:
- **AgentRegistry** (293 lines) -- thin GenServer: ETS ownership, message routing, client API
- **AgentEntry** (53) -- agent map constructor, `uuid?`, `short_id`, `role_from_string`
- **EventHandler** (54) -- pure `apply_event/2`: hook event -> agent state
- **IdentityMerge** (130) -- CWD-based identity correlation across naming schemes
- **TeamSync** (105) -- TeamWatcher data merge into ETS
- **Sweep** (72) -- stale entry GC with TTL policies

All at `lib/observatory/gateway/agent_registry/`.

**Prior this session -- distribution wiring:**
- AgentSpawner rewrite: pattern matching, remote spawn via HostRegistry, overlay delegation
- ssh_tmux channels wired through Delivery, PaneMonitor, AgentRegistry
- if/cond/unless eliminated across 6 modules

**InstructionOverlay cleanup (310 -> 299):**
- De-duplicated port lookup, flattened indirection, extracted `read_existing_settings`

### Build Status
`mix compile --warnings-as-errors` clean. Zero warnings.

### Commits This Session
1. `7ee9288` refactor(fleet): pattern-match style + remote spawn wiring
2. `a174d70` refactor(registry): extract IdentityMerge + eliminate if/cond/unless
3. `d7c70a3` refactor(registry): decompose AgentRegistry into focused submodules

### Module Sizes After Refactor
- AgentRegistry: 293, AgentEntry: 53, EventHandler: 54, IdentityMerge: 130, Sweep: 72, TeamSync: 105
- AgentSpawner: 266 (focused, single purpose -- spawn pipeline)
- InstructionOverlay: 299 (cohesive -- generate all session files)

### Next Steps (ordered)
1. **"Space" concept** -- extra namespacing on top of group_id (discussed but not implemented)
2. **Archon LLM wiring** -- connect Archon to Claude API with AshAi tools
3. **Archon chat UI** -- dashboard drawer/panel for conversing with Archon
4. Legacy ETS elimination tasks (38-40 in tasks.jsonl): CommandQueue, TeamWatcher, Mailbox
5. Ash Fleet domain generic actions + code interfaces (task 42)
6. ICHOR IV rename (task 31, deferred)

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
- After code changes, server must be restarted (Reactor steps don't auto-reload)

### Key Decisions
- AgentSpawner's `capability_to_role` kept separate from `AgentEntry.role_from_string` -- different input domains (spawn capabilities vs TeamWatcher agent_types)
- InstructionOverlay NOT split -- its two sub-concerns (template generation + file writing) are cohesive: "prepare all files an agent session needs"
- `derive_role/1` preserved as `defdelegate` on AgentRegistry for backward compatibility with 3 external callers
