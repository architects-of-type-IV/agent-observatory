# Mode C Plan — ARCHITECTS IV HYPERVISOR OBSERVATORY
Generated: 2026-02-22

## Source FRDs (SPECS_DRAFT/requirements/frds/)

| FRD | Title | Source ADRs | FRs | UCs |
|-----|-------|-------------|-----|-----|
| FRD-006 | DecisionLog Schema | ADR-014 | FR-6.1–FR-6.9 (9) | UC-0200–UC-0208 (9) |
| FRD-007 | Gateway Schema Interceptor | ADR-013, ADR-015 | FR-7.1–FR-7.9 (9) | UC-0209–UC-0217 (9) |
| FRD-008 | Causal DAG & Topology Engine | ADR-016, ADR-017 | FR-8.1–FR-8.13 (13) | UC-0230–UC-0249 (20) |
| FRD-009 | Entropy Loop Detection | ADR-018, ADR-015, ADR-021 | FR-9.1–FR-9.11 (11) | UC-0242–UC-0253 (12) |
| FRD-010 | Gateway Lifecycle | ADR-019, ADR-020 | FR-10.1–FR-10.12 (12) | UC-0260–UC-0279 (20) |
| FRD-011 | HITL Intervention API | ADR-021 | FR-11.1–FR-11.11 (11) | UC-0271–UC-0282 (12) |
| FRD-012 | Hypervisor UI Architecture | ADR-022 | FR-12.1–FR-12.13 (13) | UC-0300–UC-0313 (14) |

## Dependency Graph

```
Phase 1: DecisionLog Schema (FRD-006)
    └── Phase 2: Gateway Core (FRD-007)
            ├── Phase 3: Topology & Entropy (FRD-008, FRD-009)
            │       └── Phase 4: Gateway Infrastructure & HITL (FRD-010, FRD-011)
            │               └── Phase 5: Hypervisor UI (FRD-012)
            └── Phase 4: Gateway Infrastructure & HITL
```

## Phase Assignments

| Phase | Title | FRDs | ADRs | Rationale |
|-------|-------|------|------|-----------|
| 1 | decision-log-schema | FRD-006 | ADR-014 | Core message envelope; all other modules consume DecisionLog |
| 2 | gateway-core | FRD-007 | ADR-013, ADR-015 | HTTP ingress + validation; depends on DecisionLog struct |
| 3 | topology-and-entropy | FRD-008, FRD-009 | ADR-016, ADR-017, ADR-018 | ETS-backed DAG + sliding window; both consume validated logs |
| 4 | gateway-infrastructure-and-hitl | FRD-010, FRD-011 | ADR-019, ADR-020, ADR-021 | Lifecycle services + operator control; depends on gateway core |
| 5 | hypervisor-ui | FRD-012 | ADR-022 | Six-view LiveView shell; depends on all backend phases |

## Section Design

### Phase 1: DecisionLog Schema
- 1.1 DecisionLog Module & Embedded Schema (FR-6.1, FR-6.2, FR-6.3)
- 1.2 Action Status Enum & Causal Link Fields (FR-6.4, FR-6.5, FR-6.6)
- 1.3 Entropy Score Overwrite & JSON Deserialization (FR-6.7, FR-6.8, FR-6.9)

### Phase 2: Gateway Core
- 2.1 SchemaInterceptor Module & Validation Contract (FR-7.1, FR-7.2)
- 2.2 HTTP Endpoint & 422 Rejection (FR-7.3, FR-7.4)
- 2.3 SchemaViolationEvent & PubSub (FR-7.5, FR-7.6, FR-7.7)
- 2.4 Topology Node State & Post-Validation Routing (FR-7.8, FR-7.9)

### Phase 3: Topology & Entropy
- 3.1 CausalDAG ETS Store (FR-8.1, FR-8.2, FR-8.3, FR-8.4)
- 3.2 DAG Query API & Pruning (FR-8.5, FR-8.6, FR-8.7, FR-8.8)
- 3.3 Canvas Topology Renderer (FR-8.9, FR-8.10, FR-8.11, FR-8.12, FR-8.13)
- 3.4 EntropyTracker Sliding Window (FR-9.1, FR-9.2, FR-9.3)
- 3.5 Entropy Alerting & Severity (FR-9.4, FR-9.5, FR-9.6, FR-9.7)
- 3.6 Entropy PubSub & SchemaInterceptor Integration (FR-9.8, FR-9.9, FR-9.10, FR-9.11)

### Phase 4: Gateway Infrastructure & HITL
- 4.1 HeartbeatManager GenServer (FR-10.1, FR-10.2, FR-10.3, FR-10.4)
- 4.2 CronScheduler & DB Schema (FR-10.5, FR-10.6, FR-10.7, FR-10.8)
- 4.3 WebhookRouter Retry & DLQ (FR-10.9, FR-10.10, FR-10.11, FR-10.12)
- 4.4 HITLRelay State Machine (FR-11.1, FR-11.2, FR-11.3, FR-11.4)
- 4.5 HITL HTTP Endpoints & Auth (FR-11.5, FR-11.6, FR-11.7, FR-11.8)
- 4.6 Auto-Pause & Operator Actions (FR-11.9, FR-11.10, FR-11.11)

### Phase 5: Hypervisor UI
- 5.1 Six-View Navigation Shell (FR-12.1, FR-12.2, FR-12.3, FR-12.4)
- 5.2 Fleet Command View (FR-12.5, FR-12.6)
- 5.3 Session Cluster & Registry Views (FR-12.7, FR-12.8)
- 5.4 Scheduler & Forensic Inspector Views (FR-12.9, FR-12.10)
- 5.5 God Mode View & Global Instructions (FR-12.11, FR-12.12, FR-12.13)

## Estimated Totals

| Level | Count |
|-------|-------|
| Phases | 5 |
| Sections | 20 |
| Tasks (est.) | ~60 |
| Subtasks (est.) | ~200 |

## Output Paths

- Phase files: `SPECS_DRAFT/implementation/{N}-{name}.md`
- Section files: `SPECS_DRAFT/implementation/{N.M}-{name}.md`
- Task files: `SPECS_DRAFT/implementation/{N.M.K}-{name}.md`
- Subtask files: `SPECS_DRAFT/implementation/{N.M.K.L}-{name}.md`
- Index: `SPECS_DRAFT/implementation/index.jsonl`
