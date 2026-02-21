# Mode B Plan — ARCHITECTS IV HYPERVISOR OBSERVATORY
Generated: 2026-02-21

## Source ADRs (SPECS_DRAFT/decisions/, all treated as approved)

- ADR-013: Hypervisor Platform Scope
- ADR-014: DecisionLog Universal Message Envelope
- ADR-015: Gateway Schema Interceptor
- ADR-016: Canvas-Based Topology Map Renderer
- ADR-017: Causal DAG via parent_step_id
- ADR-018: Entropy Score as Loop Detection Primitive
- ADR-019: Heartbeat and Leader Election for Gateway
- ADR-020: Webhook Reliability: Retry + DLQ
- ADR-021: HITL Manual Intervention API
- ADR-022: Six-View UI Information Architecture

## FRD Groupings

| FRD | Title | Source ADRs | Batch |
|-----|-------|-------------|-------|
| FRD-006 | DecisionLog Schema | ADR-014 | A |
| FRD-007 | Gateway Schema Interceptor | ADR-013, ADR-015 | A |
| FRD-008 | Causal DAG & Topology Engine | ADR-016, ADR-017 | B |
| FRD-009 | Entropy Loop Detection | ADR-018 | B |
| FRD-010 | Gateway Lifecycle | ADR-019, ADR-020 | C |
| FRD-011 | HITL Intervention API | ADR-021 | C |
| FRD-012 | Hypervisor UI Architecture | ADR-022 | D |

## Batch Assignments

| Batch | Agent | FRDs | UC Range |
|-------|-------|------|----------|
| A | writer-1 | FRD-006, FRD-007 | UC-0200 to UC-0229 |
| B | writer-2 | FRD-008, FRD-009 | UC-0230 to UC-0259 |
| C | writer-3 | FRD-010, FRD-011 | UC-0260 to UC-0299 |
| D | writer-4 | FRD-012 | UC-0300 to UC-0329 |

## Output directories

- FRDs: SPECS_DRAFT/requirements/frds/
- UCs: SPECS_DRAFT/requirements/use-cases/
- Gates: SPECS_DRAFT/requirements/gate-1-report.md, gate-2-report.md
