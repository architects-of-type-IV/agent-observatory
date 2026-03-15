# Genesis Nodes: MES -> Monad Method Pipeline

**Date:** 2026-03-15
**Status:** Approved

## Vision

MES teams produce PROPOSED project briefs. Instead of building directly, the Architect runs Mode A/B/C (Monad Method) on the brief using Workshop teams. The output is a Genesis Node with full planning artifacts, culminating in a DAG-ready implementation roadmap.

## Pipeline

```
MES Team -> PROPOSED brief -> Mode A (ADRs) -> Mode B (FRDs/UCs) -> Mode C (Roadmap) -> DAG -> Swarm
```

## Domain Model: `Ichor.Genesis` (SQLite)

| Resource | Key Fields | Relationships |
|----------|-----------|---------------|
| Node | title, description, brief, stakeholders, constraints, status (discover/define/build/complete) | has_many: all below |
| ADR | code, title, status (pending/proposed/accepted/rejected), content, research_complete | belongs_to: node |
| Feature | code, title, content, adr_codes | belongs_to: node |
| UseCase | code, title, content, feature_code | belongs_to: node |
| Checkpoint | title, mode (discover/define/build), content, summary | belongs_to: node |
| Conversation | title, mode, content, participants | belongs_to: node |
| Phase | number, title, goals, status, governed_by | belongs_to: node |
| Section | number, title, goal | belongs_to: phase |
| Task | number, title, governed_by, parent_uc, status | belongs_to: section |
| Subtask | number, title, goal, allowed_files, blocked_by, steps, done_when, status, owner | belongs_to: task |

MES `Project` gets `genesis_node_id` FK linking to local Node.

## MCP Tools (extend existing server)

| Tool | Scoped to |
|------|-----------|
| create_genesis_node | coordinator |
| create_adr, update_adr, list_adrs | Mode A agents |
| create_feature, list_features | Mode B agents |
| create_use_case, list_use_cases | Mode B agents |
| create_conversation, list_conversations | all mode agents |
| create_checkpoint | coordinator |
| create_phase, create_task, create_subtask, list_phases | Mode C agents |
| gate_check | gate agents |

Tool scoping via agent prompt (not MCP endpoint filtering).

## UI: MES Detail Panel

Mode actions bar on PROPOSED projects:
```
[ Mode A: Discover ] [ Mode B: Define ] [ Mode C: Build ] [ Gate Check ]
```

Clicking a mode: modal with "Auto-spawn team" (default) or "Select Workshop team" dropdown. Creates Genesis Node from brief if not yet created, spawns/assigns team.

Genesis artifact summary section below project spec: ADR/Feature/UC/Conversation counts, Checkpoint timeline.

Gate Check: spawns review team, produces readiness report (soft gate).

Mode C "Generate DAG" button: converts Subtask hierarchy to tasks.jsonl for /dag run.

## Component Split

| File | Functions |
|------|----------|
| mes_components.ex | mes_view/1 (orchestrator, delegates all) |
| mes_feed_components.ex | feed/1, feed_row/1, feed_header/1 |
| mes_detail_components.ex | project_detail/1 |
| mes_genesis_components.ex | genesis_panel/1 |
| mes_gate_components.ex | gate_report/1 |
| mes_status_components.ex | status_badge/1, action_button/1, scheduler_status/1 |
| mes_section_components.ex | detail_section/1, tag_list/1, mono_block/1 |
| mes_research_components.ex | (already exists) |

## Future: Genesis Sync

When hardware is restored, a sync module pushes Nodes + artifacts to Genesis app's Postgres via its RPC API. Schema mirrors Genesis 1:1 by design.
