# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Distribution Foundation Complete (2026-03-09)

### Just Completed

1. **Dead code removal** -- removed tree API (`children/1`, `parent/1`, `chain_of_command/1`, `reparent/2`, `add_child/2`, `remove_child/2`, `build_chain/2`). AgentRegistry: 894 -> 669 lines.

2. **Distribution foundation** -- BEAM clustering support for multi-host agent fleet:
   - `Fleet.HostRegistry` GenServer (169 lines) -- tracks BEAM cluster nodes, auto-discovers via `:net_kernel.monitor_nodes/2`, uses `:pg` for cluster-wide visibility
   - `AgentProcess` joins `:pg` group `{:agent, id}` -- new APIs: `lookup_cluster/1`, `list_cluster/0`
   - `TeamSupervisor` joins `:pg` group `{:team, name}` -- new API: `list_cluster/0`
   - `FleetSupervisor.spawn_agent_on/2` -- routes local vs remote via `:rpc.call`
   - `AgentSpawner` accepts `:host` option -- routes to local or remote node
   - `:pg` scope `:observatory_agents` started in application supervisor

3. **Prior session work** -- Feed UI, Launch button fix, OutputCapture + TmuxDiscovery extraction

### Architecture: Distribution Model

- **Supervision stays local** -- each node supervises its own AgentProcesses
- **Discovery is global** -- `:pg` groups span the BEAM cluster
- **Messaging works** -- `GenServer.call/cast` with PIDs works across connected nodes
- **PubSub works** -- `Phoenix.PubSub` is already distribution-aware
- **DNSCluster** -- already in supervision tree (set to `:ignore`), configure for production

### Next Steps (ordered)

1. **Clustering config** -- set up node naming and `DNSCluster` query for auto-discovery
2. **AgentRegistry ETS distribution** -- currently node-local; long-term: BEAM-native fleet via `:pg` replaces ETS
3. **Remote tmux delivery** -- SSH-based tmux commands for agents on remote hosts
4. **AgentSpawner refactor** -- 318 lines, over 200-line limit. Extract overlay/hooks generation.

### Remaining (backlog)
- Memories integration, Archon LLM, Archon chat UI
- Phase 8: ICHOR IV rename (deferred)

### Build Status
`mix compile --warnings-as-errors` clean.
