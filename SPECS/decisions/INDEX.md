---
title: Observatory Architecture Decision Log
generated: 2026-02-21
sessions_analyzed: 25
date_range: 2026-02-14 to 2026-02-21
---
# Observatory Architecture Decision Log

## Summary

| Metric | Count |
|--------|-------|
| Sessions analyzed | 25 |
| Decisions extracted | 12 |
| Previously undocumented | 4 |
| Expanded from partial docs | 4 |
| Validated existing docs | 4 |

## Decision Index

### UI Architecture

| ADR | Title | Date | Status |
|-----|-------|------|--------|
| [ADR-001](ADR-001-swarm-control-center-nav.md) | Swarm Control Center Navigation Restructure | 2026-02-21 | accepted |
| [ADR-002](ADR-002-agent-block-feed.md) | Feed Restructured to Agent Blocks | 2026-02-21 | accepted |
| [ADR-003](ADR-003-unified-control-plane.md) | Three-Tab Merge into Unified Control Plane | 2026-02-21 | accepted |
| [ADR-008](ADR-008-default-view-evolution.md) | Default View Mode Evolution | 2026-02-21 | accepted |
| [ADR-010](ADR-010-component-file-split.md) | Component File Split Pattern | 2026-02-21 | accepted |
| [ADR-011](ADR-011-handler-delegation.md) | Handler Delegation Pattern | 2026-02-14 | accepted |

### Messaging & Data

| ADR | Title | Date | Status |
|-----|-------|------|--------|
| [ADR-004](ADR-004-messaging-architecture.md) | Messaging Aligned with Claude Code Native | 2026-02-15 | accepted |
| [ADR-005](ADR-005-ets-over-database.md) | ETS for Messaging over Database | 2026-02-14 | accepted |
| [ADR-006](ADR-006-dead-ash-domains.md) | Dead Ash Domains Replaced with Plain Modules | 2026-02-15 | accepted |
| [ADR-012](ADR-012-dual-data-sources.md) | Dual Data Source Architecture | 2026-02-14 | accepted |

### Infrastructure

| ADR | Title | Date | Status |
|-----|-------|------|--------|
| [ADR-007](ADR-007-swarm-monitor-design.md) | SwarmMonitor and ProtocolTracker Design | 2026-02-21 | accepted |
| [ADR-009](ADR-009-roadmap-naming.md) | Flat File Roadmaps with Dotted Numbering | 2026-02-14 | accepted |

## Conversation Artifacts

Formal "thinking trail" documents that trace from raw sessions to ADRs.

| Conversation | Title | ADRs |
|--------------|-------|------|
| [CONV-001](../conversations/CONV-001-swarm-control-center.md) | Swarm Control Center Design | ADR-001, ADR-002, ADR-003, ADR-007, ADR-008, ADR-010 |
| [CONV-002](../conversations/CONV-002-messaging-architecture.md) | Messaging Architecture Investigation | ADR-004, ADR-005, ADR-006 |
| [CONV-003](../conversations/CONV-003-team-inspector.md) | Team Inspector Design | ADR-009, ADR-011, ADR-012 |

Traceability chain: `Session JSONL -> Conversation -> ADR -> FRD -> UC`

## Session Cross-Reference

Unique sessions that contributed decisions:

| Session ID | Date | Conversation | Decisions |
|------------|------|--------------|-----------|
| `8585be9e-149a-4133-bed8-ef55dd380dc9` | 2026-02-14 | CONV-003 | ADR-005, ADR-009, ADR-011, ADR-012 |
| `16482e4f-50b6-4152-99ce-82a7f7e604c4` | 2026-02-15 | CONV-002 | ADR-004, ADR-005, ADR-006 |
| `3b9cd554-74a4-46c3-9db6-6d15f99fc615` | 2026-02-15 | CONV-003 | ADR-011 |
| `40a5aa38-28e8-4f70-a5ba-21602f618f07` | 2026-02-15 | CONV-002 | ADR-004 |
| `1f469adb-7830-4fb9-ac26-af6d0b3fbc45` | 2026-02-21 | CONV-001 | ADR-001, ADR-002, ADR-003, ADR-007, ADR-008, ADR-010, ADR-012 |

## Dependency Graph

```
ADR-001 (Nav Restructure)
  ├── ADR-003 (Unified Control Plane)
  ├── ADR-007 (SwarmMonitor + ProtocolTracker)
  └── ADR-008 (Default View Evolution)

ADR-004 (Messaging Architecture)
  ├── ADR-005 (ETS over Database)
  └── ADR-006 (Dead Ash Domains)

ADR-012 (Dual Data Sources)
  ├── ADR-005 (ETS over Database)
  └── ADR-007 (SwarmMonitor)

ADR-010 (Component File Split)
  └── ADR-011 (Handler Delegation)

ADR-009 (Roadmap Naming) -- standalone
```
