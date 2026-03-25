# Supervision Tree
Related: [Index](INDEX.md) | [Infrastructure](infrastructure.md) | [Target Structure](target-file-structure.md)

---

## Current Supervision Tree (as of 2026-03-25)

```
Ichor.Supervisor (one_for_one)
  ├── IchorWeb.Telemetry
  ├── Ichor.Repo
  ├── Oban
  ├── Ecto.Migrator
  ├── DNSCluster
  ├── Phoenix.PubSub (Ichor.PubSub)
  ├── Registry (Ichor.Registry, :unique)
  ├── :pg scope (:ichor_agents)
  ├── Infrastructure.HostRegistry
  ├── Task.Supervisor (Ichor.TaskSupervisor)   <-- starts before RuntimeSupervisor
  │
  ├── Ichor.RuntimeSupervisor (one_for_one)
  │   ├── Registry (Ichor.Signals.ProcessRegistry, :unique)
  │   ├── DynamicSupervisor (Ichor.Signals.ProcessSupervisor)
  │   ├── Signals.PipelineSupervisor (rest_for_one)
  │   │   ├── Events.Ingress              (GenStage producer)
  │   │   └── Signals.Router             (GenStage consumer)
  │   ├── MemoryStore
  │   ├── Signals.EventStream            (ETS event store + broadcaster)
  │   ├── Infrastructure.TmuxDiscovery
  │   ├── Infrastructure.OutputCapture
  │   ├── Projector.AgentWatchdog
  │   ├── Projector.ProtocolTracker
  │   ├── Projector.SignalBuffer
  │   ├── Projector.SignalManager
  │   └── Projector.TeamWatchdog
  │
  ├── Fleet.Supervisor (DynamicSupervisor)      <-- was Infrastructure.FleetSupervisor
  │   ├── Fleet.AgentProcess (per agent, dynamic)
  │   └── Fleet.TeamSupervisor (per team, dynamic)
  │
  ├── Projector.FleetLifecycle
  ├── Projector.CleanupDispatcher
  │
  ├── Factory.LifecycleSupervisor (one_for_one)   <-- was rest_for_one
  │   └── DynamicSupervisor (Ichor.Factory.BuildRunSupervisor)
  │
  ├── Projector.MesProjectIngestor           <-- extracted from LifecycleSupervisor
  ├── Projector.MesResearchIngestor          <-- extracted from LifecycleSupervisor
  ├── Projector.CompletionHandler            <-- moved from Factory, extracted from LifecycleSupervisor
  ├── Projector.TeamSpawnHandler             <-- moved from Workshop
  ├── DynamicSupervisor (Ichor.Factory.PlanRunSupervisor)
  ├── DynamicSupervisor (Ichor.Factory.PipelineRunSupervisor)   <-- was DynRunSupervisor
  └── IchorWeb.Endpoint
```

**Key changes from prior design:**
- `Task.Supervisor` now starts before `RuntimeSupervisor` (OutputCapture and AgentProcess both use `Ichor.TaskSupervisor`)
- `LifecycleSupervisor` is `one_for_one` (was `rest_for_one`), owns only `BuildRunSupervisor`
- 5 projectors extracted to top-level app children: `MesProjectIngestor`, `MesResearchIngestor`, `CompletionHandler`, `TeamSpawnHandler` (from Workshop), plus `FleetLifecycle` and `CleanupDispatcher`
- `Fleet.Supervisor` extracted from `Infrastructure` into its own `fleet/` namespace (hexagonal reorg)
- `Orchestration.TeamLaunch` extracted from `Infrastructure` into its own `orchestration/` namespace
- `HITLRelay` removed entirely (HITL subsystem deleted)
- `DynRunSupervisor` renamed to `PipelineRunSupervisor`
- `Signals.PipelineSupervisor` (`rest_for_one`) wraps Ingress + Router -- Router restart re-subscribes to a live Ingress

## Prior Target Supervision Tree

The earlier target described in the architecture audit (Runtime.Supervisor grouping) has been partially implemented. The actual tree above reflects the current state. The `Fleet.Runtime` / `Events.Runtime` / `Projects.Runtime` naming was not adopted -- the existing `FleetSupervisor`, `EventStream`, and `BuildRunSupervisor` names were kept.

---

## Supervisor Strategies (current)

| Supervisor | Strategy | Notes |
|-----------|---------|-------|
| `Ichor.Supervisor` | `one_for_one` | Top-level application supervisor |
| `Ichor.RuntimeSupervisor` | `one_for_one` | Runtime services; independent subsystems |
| `Signals.PipelineSupervisor` | `rest_for_one` | Ingress + Router must restart together |
| `Signals.ProcessSupervisor` | `one_for_one` (DynSup) | Per-session SignalProcess accumulator processes |
| `Fleet.Supervisor` | `one_for_one` (DynSup) | Each AgentProcess is independent |
| `Factory.LifecycleSupervisor` | `one_for_one` | Was rest_for_one; only owns BuildRunSupervisor now |
| `Factory.BuildRunSupervisor` | `one_for_one` (DynSup) | Build runs are independent |
| `Factory.PlanRunSupervisor` | `one_for_one` (DynSup) | Planning runs are independent |
| `Factory.PipelineRunSupervisor` | `one_for_one` (DynSup) | Pipeline runs (renamed from DynRunSupervisor) |
| `TeamSupervisor` | `:temporary` dynamic per team | Teams are ephemeral; do not restart |
| ~~`Mesh.Supervisor`~~ | -- | Deleted in f20ac4b |

---

## GenServer Status (current)

| Process | Status | Notes |
|---------|--------|-------|
| `Signals.EventStream` | Keep GenServer + ETS | Owns ETS write path + subscription fanout |
| `Fleet.AgentProcess` | Keep GenServer | IS the agent. Holds mailbox, backend, live state. |
| `Fleet.Supervisor` | Keep DynSup | Owns the AgentProcess lifecycle tree |
| `Events.Ingress` | GenStage producer | Bridges domain events into demand-driven signal pipeline |
| `Signals.Router` | GenStage consumer | Routes events to SignalProcess accumulators |
| `Signals.SignalProcess` | Transient GenServer | Per {module, key} accumulator; idle timeout 5 min |
| `Factory.Runner` (build runs) | Keep GenServer | Monitors live run state, manages lifecycle |
| `Projector.TeamWatchdog` | Signal subscriber | Enqueues Oban cleanup jobs on run_complete |
| `Projector.AgentWatchdog` | GenServer (5s tick) | Fleet health, crash detection, escalation |
| ~~`Infrastructure.HITLRelay`~~ | DELETED | HITL subsystem removed (-1,002 lines) |
| ~~`Factory.MesScheduler`~~ | Replaced by Oban cron | `Workers.MesTick` drives the MES schedule |
| ~~`Signals.Buffer`~~ | Replaced by `Projector.SignalBuffer` | Moved to Projector namespace |

---

## Failure Domain Groups

The current flat supervision tree lumps unrelated processes together. Any supervisor crash (unlikely but possible) kills all 14 children.

Target groups by failure domain so a crash in one subsystem does not affect others:

| Group | Children | Impact if group crashes |
|-------|----------|------------------------|
| `Events.Runtime` | ETS event store + broadcaster | Signal delivery stops; no agent processes affected |
| `Fleet.Runtime` | All AgentProcess + TeamSupervisor instances | Agents lose BEAM-side mailbox; tmux processes continue |
| `Projects.Runtime` | Active RunManager instances | Run lifecycle monitoring stops; Ash state preserved |
| `Transport.Cron` | Cron execution runtime | Scheduled deliveries stop; Oban picks up on restart |
| Oban | All background job queues | Retry queues pause; Ash state preserved |

---

## Notes on the ETS / GenServer Split

`Events.Runtime` (the event store) holds ETS tables for:
- The event ring buffer (all recent hook events)
- The session activity map (last-seen timestamps per session)
- The message delivery log

The GenServer serializes **writes** and manages **subscriptions**. Reads go directly to ETS. This is the correct split: `GenServer.call` for writes gives you serialization guarantees without bottlenecking concurrent readers (multiple LiveViews, AgentWatchdog all read simultaneously).

The `Buffer` GenServer was a mistake because its only job was incrementing a counter -- `:atomics` is correct for that.
