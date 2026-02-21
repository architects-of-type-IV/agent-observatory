# ARCHITECTS IV HYPERVISOR OBSERVATORY
## SPECS_DRAFT Index

**Phase:** Hypervisor for Machine Cognition
**Date:** 2026-02-21

---

## Project Brief

- [PROJECT-BRIEF.md](PROJECT-BRIEF.md) — Full requirements, architecture, and ADR extraction map

---

## ADR Index

### Existing ADRs (Observatory Swarm Monitor — carry forward)

| ADR | Title | Status |
|-----|-------|--------|
| ADR-001 | Swarm Control Center Navigation Restructure | accepted (superseded by ADR-022 for nav) |
| ADR-002 | Agent Block Feed | accepted |
| ADR-003 | Three-Tab Merge into Unified Control Plane | accepted (superseded by ADR-022) |
| ADR-004 | Messaging Architecture | accepted |
| ADR-005 | ETS over Database | accepted |
| ADR-006 | Dead Ash Domains | accepted |
| ADR-007 | Swarm Monitor Design | accepted |
| ADR-008 | Default View Evolution | accepted |
| ADR-009 | Roadmap Naming | accepted |
| ADR-010 | Component File Split | accepted |
| ADR-011 | Handler Delegation | accepted |
| ADR-012 | Dual Data Sources | accepted |

### New ADRs (Hypervisor — proposed)

| ADR | Title | Decision Area | Status |
|-----|-------|---------------|--------|
| [ADR-013](decisions/ADR-013-hypervisor-platform-scope.md) | Hypervisor Platform Scope | Platform evolution: Observatory → Hypervisor | proposed |
| [ADR-014](decisions/ADR-014-decision-log-envelope.md) | DecisionLog Universal Message Envelope | Schema standard for all Gateway messages | proposed |
| [ADR-015](decisions/ADR-015-gateway-schema-interceptor.md) | Gateway Schema Interceptor | Validation, rejection, and violation logging | proposed |
| [ADR-016](decisions/ADR-016-canvas-topology-renderer.md) | Canvas-Based Topology Map Renderer | Macro fleet visualization engine choice | proposed |
| [ADR-017](decisions/ADR-017-causal-dag-parent-step-id.md) | Causal DAG via parent_step_id | Topology and drill-down graph construction | proposed |
| [ADR-018](decisions/ADR-018-entropy-score-loop-detection.md) | Entropy Score as Loop Detection Primitive | Algorithmic agent loop detection | proposed |
| [ADR-019](decisions/ADR-019-heartbeat-leader-election.md) | Heartbeat and Leader Election for Gateway | Multi-instance cron dispatch safety | proposed |
| [ADR-020](decisions/ADR-020-webhook-retry-dlq.md) | Webhook Reliability: Retry + DLQ | Outbound webhook durability pattern | proposed |
| [ADR-021](decisions/ADR-021-hitl-intervention-api.md) | HITL Manual Intervention API | Operator control path: Pause/Rewrite/Inject | proposed |
| [ADR-022](decisions/ADR-022-six-view-ui-architecture.md) | Six-View UI Information Architecture | Hypervisor UI sitemap and view responsibilities | proposed |

---

## Dependency Graph

```
ADR-013 (Platform Scope)
    ├── ADR-014 (DecisionLog Schema)
    │       ├── ADR-015 (Schema Interceptor)
    │       ├── ADR-017 (Causal DAG)
    │       └── ADR-018 (Entropy Score)
    ├── ADR-016 (Topology Renderer) ← ADR-017
    ├── ADR-019 (Heartbeat + Leader Election)
    │       └── ADR-020 (Webhook DLQ)
    ├── ADR-021 (HITL API) ← ADR-018
    └── ADR-022 (Six-View UI) ← ADR-016, ADR-017, ADR-021
```

---

## Key Modules to Create

### Gateway Layer (`lib/observatory/gateway/`)
- `schema_interceptor.ex` — ADR-015
- `capability_map.ex` — ADR-019
- `heartbeat_manager.ex` — ADR-019
- `cron_scheduler.ex` — ADR-019
- `webhook_router.ex` — ADR-020
- `hitl_relay.ex` — ADR-021
- `entropy_tracker.ex` — ADR-018
- `topology_builder.ex` — ADR-016

### Mesh Layer (`lib/observatory/mesh/`)
- `decision_log.ex` — ADR-014
- `causal_dag.ex` — ADR-017

### UI Layer (`lib/observatory_web/components/`)
- `fleet_command_components.ex` — ADR-022 View 1
- `session_cluster_components.ex` — ADR-022 View 2
- `registry_components.ex` — ADR-022 View 3
- `scheduler_components.ex` — ADR-022 View 4
- `forensic_components.ex` — ADR-022 View 5
- `god_mode_components.ex` — ADR-022 View 6

### JS Hooks (`assets/js/hooks/`)
- `topology_map.js` — ADR-016

---

## New PubSub Topics

| Topic | Producer | Consumers |
|-------|----------|-----------|
| `gateway:violations` | SchemaInterceptor | Fleet Command, Forensic Inspector |
| `gateway:topology` | TopologyBuilder | Fleet Command (Topology Map) |
| `gateway:entropy_alerts` | EntropyTracker | Session Cluster, Fleet Command |
| `gateway:webhooks` | WebhookRouter | Scheduler, Forensic Inspector |
| `session:dag:{session_id}` | CausalDAG | Session Cluster drill-down |
| `session:hitl:{session_id}` | HITLRelay | Session Cluster HITL Console |

---

## New DB Migrations Required

| Table | Purpose | ADR |
|-------|---------|-----|
| `gateway_heartbeats` | Agent liveness tracking | ADR-019 |
| `cron_jobs` | Scheduled task registry | ADR-019 |
| `webhook_deliveries` | Outbound webhook delivery + DLQ | ADR-020 |
| `webhook_configs` | Inbound webhook routing config | ADR-020 |
| `hitl_interventions` | HITL command audit trail | ADR-021 |
| `schema_violations` | Schema violation log | ADR-015 |
