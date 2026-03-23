# Subscribers and Emitters

## Full Subscribers (subscribe + handle_info)

| Module | Subscribes to | Handles | Side effects |
|--------|--------------|---------|--------------|
| `Infrastructure.Subscribers.SessionLifecycle` | `:fleet` | session_started/ended, team_create/delete_requested | Spawns/terminates OTP processes |
| `Infrastructure.Subscribers.SessionCleanupDispatcher` | `:cleanup` | session_cleanup_needed | Oban insert (DisbandTeam, KillSession) |
| `Factory.Subscribers.RunCleanupDispatcher` | `:cleanup` | run_cleanup_needed | Oban insert (ArchiveRun, ResetTasks) |
| `Archon.SignalManager` | ALL categories | Every signal | Pure state accumulation (counts, attention queue) |
| `Factory.ProjectIngestor` | `:messages` | message_delivered (to operator, from MES) | Ash write (Project.create), emits mes_project_created |
| `Factory.ResearchIngestor` | `:mes` | mes_project_created | HTTP to Memories API, emits mes_research_ingested |
| `Factory.CompletionHandler` | `:pipeline` | pipeline_completed | BEAM hot-load (PluginLoader), Ash writes |
| `MemoriesBridge` | ALL categories | Every signal (except ignored) | HTTP to Memories API (30s flush) |
| `Infrastructure.AgentProcess` | `:agent_event` (scoped) | agent_event | ETS write (registry), emits fleet_changed |
| `Mesh.EventBridge` | `:events`, `:dag_delta` (scoped) | new_event, dag_delta | CausalDAG ETS write, emits decision_log/topology_snapshot |
| `Workshop.TeamSpawnHandler` | `:fleet` | team_spawn_requested | TeamLaunch.launch, emits team_spawn_ready/failed |

---

## Hybrid: Subscribe + Re-emit

| Module | Subscribes to | Emits |
|--------|--------------|-------|
| `Archon.TeamWatchdog` | `:fleet`, `:pipeline`, `:planning`, `:monitoring` | run_cleanup_needed, session_cleanup_needed |

---

## Scoped Await (temporary subscribe, block, unsubscribe)

| Module | Pattern |
|--------|---------|
| `Workshop.Spawn` | Emits team_spawn_requested, blocks on receive for team_spawn_ready/failed |

---

## Emit-Only (no subscribe)

| Module | Signals emitted |
|--------|----------------|
| `Infrastructure.AgentLifecycle` | agent_started/paused/resumed/stopped |
| `Infrastructure.FleetSupervisor` | team_disbanded |
| `Infrastructure.TeamSupervisor` | team_created |
| `Infrastructure.TmuxDiscovery` | fleet_changed, agent_reaped, agent_discovered |
| `Infrastructure.OutputCapture` | terminal_output (scoped) |
| `Infrastructure.HITL.Events` | gate_open/close (scoped), decision_log, hitl_auto_released |
| `Infrastructure.HostRegistry` | hosts_changed |
| `Factory.Spawn` | pipeline_ready, planning_team_ready, mes_team_killed, etc. |
| `Factory.Runner` | run_complete, run_terminated, pipeline_health_report, etc. |
| `Factory.Loader` | pipeline_created |
| `Factory.LifecycleSupervisor` | mes_operator_ensured |
| `Factory.MesScheduler` | mes_scheduler_paused/resumed |
| `Factory.PluginLoader` | mes_plugin_loaded |
| `Factory.Workers.*` | Various (pipeline_status, pipeline_archived, mes_tick, etc.) |
| `MemoryStore` | memory_changed (scoped) |
