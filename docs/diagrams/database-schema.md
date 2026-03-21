# Database Schema -- ICHOR IV

Generated from source on 2026-03-21. All `AshSqlite.DataLayer` persisted tables and `data_layer: :embedded` resources.

Related: [Glossary](../plans/GLOSSARY.md) | [Architecture Diagrams](architecture.md)

SQLite stores UUIDs as text. Timestamps are ISO 8601 text. Arrays are JSON arrays.

---

## Workshop Domain

Tables: `workshop_teams`, `workshop_team_members`, `workshop_agent_types`

```mermaid
erDiagram
    workshop_teams {
        text id PK "uuid, NOT NULL"
        text name "NOT NULL, UNIQUE"
        text strategy "NOT NULL, default: one_for_one"
        text default_model "NOT NULL, default: sonnet"
        text cwd "default: empty string"
        json agents "AgentSlot[], default: []"
        json spawn_links "SpawnLink[], default: []"
        json comm_rules "CommRule[], default: []"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    workshop_team_members {
        text id PK "uuid, NOT NULL"
        text team_id FK "NOT NULL"
        text agent_type_id FK "nullable"
        integer slot "NOT NULL"
        integer position "NOT NULL, default: 0"
        text name "NOT NULL"
        text capability "NOT NULL, default: builder"
        text model "NOT NULL, default: sonnet"
        text permission "NOT NULL, default: default"
        text extra_instructions "NOT NULL, default: empty"
        text file_scope "NOT NULL, default: empty"
        text quality_gates "NOT NULL, default: empty"
        json tool_scope "string[], NOT NULL, default: []"
        integer canvas_x "NOT NULL, default: 40"
        integer canvas_y "NOT NULL, default: 30"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    workshop_agent_types {
        text id PK "uuid, NOT NULL"
        text name "NOT NULL, UNIQUE"
        text capability "NOT NULL, default: builder"
        text default_model "NOT NULL, default: sonnet"
        text default_permission "NOT NULL, default: default"
        text default_persona "NOT NULL, default: empty"
        text default_file_scope "NOT NULL, default: empty"
        text default_quality_gates "NOT NULL, default: mix compile"
        json default_tools "string[], NOT NULL, default: []"
        text color "NOT NULL, default: empty"
        integer sort_order "NOT NULL, default: 0"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    workshop_teams ||--o{ workshop_team_members : "has many (team_id)"
    workshop_agent_types ||--o{ workshop_team_members : "referenced by (agent_type_id)"
```

---

## Factory Domain

Tables: `projects`, `pipelines`, `pipeline_tasks`

```mermaid
erDiagram
    projects {
        text id PK "uuid, NOT NULL"
        text title "NOT NULL"
        text description "NOT NULL"
        json stakeholders "string[], default: []"
        json constraints "string[], default: []"
        text planning_stage "discover|define|build|complete, default: discover"
        text output_kind "NOT NULL, default: plugin"
        text plugin "nullable"
        text signal_interface "nullable"
        text topic "nullable"
        text version "nullable, default: 0.1.0"
        json features "string[], default: []"
        json use_cases "string[], default: []"
        text architecture "nullable"
        json dependencies "string[], default: []"
        json signals_emitted "string[], default: []"
        json signals_subscribed "string[], default: []"
        text status "proposed|in_progress|compiled|loaded|failed, default: proposed"
        text team_name "nullable"
        text run_id "nullable"
        text picked_up_by "nullable"
        datetime picked_up_at "nullable"
        text path "nullable"
        text build_log "nullable"
        json artifacts "Artifact[], default: []"
        json roadmap_items "RoadmapItem[], default: []"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    pipelines {
        text id PK "uuid, NOT NULL"
        text label "NOT NULL"
        text source "project|imported, NOT NULL"
        text project_id "nullable (plain text, no FK)"
        text project_path "nullable"
        text tmux_session "nullable"
        text status "active|completed|failed|archived, default: active"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    pipeline_tasks {
        text id PK "uuid, NOT NULL"
        text run_id FK "NOT NULL"
        text external_id "NOT NULL"
        text subtask_id "nullable"
        text subject "NOT NULL"
        text description "nullable"
        text goal "nullable"
        json allowed_files "string[], default: []"
        json steps "string[], default: []"
        text done_when "nullable"
        json blocked_by "string[], default: []"
        text status "pending|in_progress|completed|failed, default: pending"
        text owner "nullable"
        text priority "critical|high|medium|low, default: medium"
        integer wave "nullable"
        json acceptance_criteria "string[], default: []"
        text phase_label "nullable"
        json tags "string[], default: []"
        text notes "nullable"
        datetime claimed_at "nullable"
        datetime completed_at "nullable"
        datetime inserted_at "NOT NULL"
        datetime updated_at "NOT NULL"
    }

    pipelines ||--o{ pipeline_tasks : "has many (run_id)"
```

---

## Infrastructure Domain

Tables: `webhook_deliveries`, `cron_jobs`, `hitl_intervention_events`

```mermaid
erDiagram
    webhook_deliveries {
        text id PK "uuid, NOT NULL"
        text target_url "NOT NULL"
        text payload "NOT NULL"
        text signature "nullable"
        text status "pending|delivered|failed|dead, default: pending"
        integer attempt_count "default: 0"
        datetime next_retry_at "nullable"
        text agent_id "NOT NULL"
        text webhook_id "nullable"
        datetime inserted_at "NOT NULL"
    }

    cron_jobs {
        text id PK "uuid, NOT NULL"
        text agent_id "NOT NULL"
        text payload "NOT NULL"
        datetime next_fire_at "NOT NULL"
        boolean is_one_time "NOT NULL, default: true"
        datetime inserted_at "NOT NULL"
    }

    hitl_intervention_events {
        text id PK "uuid, NOT NULL"
        text session_id "NOT NULL"
        text agent_id "nullable"
        text operator_id "NOT NULL"
        text action "pause|unpause|rewrite|inject, NOT NULL"
        json details "map, default: {}"
        datetime inserted_at "NOT NULL"
    }
```

All three tables are append-oriented. No foreign keys to other domains -- IDs matched at runtime.

---

## Embedded Resources (JSON Columns)

Stored as JSON arrays inside parent table columns. Never have their own table.

```mermaid
erDiagram
    workshop_teams {
        json agents "AgentSlot[]"
        json spawn_links "SpawnLink[]"
        json comm_rules "CommRule[]"
    }

    projects {
        json artifacts "Artifact[]"
        json roadmap_items "RoadmapItem[]"
    }

    AGENT_SLOT {
        integer id "slot number, NOT NULL"
        text agent_type_id "nullable"
        text name "NOT NULL"
        text capability "default: builder"
        text model "default: sonnet"
        text permission "default: default"
        text persona "default: empty"
        text file_scope "default: empty"
        text quality_gates "default: empty"
        json tools "string[], default: []"
        integer x "canvas x"
        integer y "canvas y"
    }

    SPAWN_LINK {
        integer from "source slot, NOT NULL"
        integer to "dest slot, NOT NULL"
    }

    COMM_RULE {
        integer from "source slot, NOT NULL"
        integer to "dest slot, NOT NULL"
        text policy "default: allow"
        integer via "relay slot, nullable"
    }

    ARTIFACT {
        text id "uuid"
        text kind "brief|adr|feature|use_case|checkpoint|conversation, NOT NULL"
        text title "NOT NULL"
        text content "nullable"
        text code "nullable (ADR-001, FRD-002)"
        text status "pending|proposed|accepted|rejected, nullable"
        text mode "discover|define|build|gate_a|gate_b|gate_c, nullable"
        text summary "nullable"
        json adr_codes "string[], default: []"
        text feature_code "nullable"
        json participants "string[], default: []"
    }

    ROADMAP_ITEM {
        text id "uuid"
        text kind "phase|section|task|subtask, NOT NULL"
        integer number "NOT NULL"
        text title "NOT NULL"
        text status "pending|in_progress|completed|failed, default: pending"
        json governed_by "string[], default: []"
        json goals "string[], default: []"
        text goal "nullable"
        text parent_uc "nullable"
        json allowed_files "string[], default: []"
        json blocked_by "string[], default: []"
        json steps "string[], default: []"
        text done_when "nullable"
        text owner "nullable"
        text parent_id "uuid of parent, nullable"
    }

    workshop_teams ||--o{ AGENT_SLOT : "agents JSON"
    workshop_teams ||--o{ SPAWN_LINK : "spawn_links JSON"
    workshop_teams ||--o{ COMM_RULE : "comm_rules JSON"
    projects ||--o{ ARTIFACT : "artifacts JSON"
    projects ||--o{ ROADMAP_ITEM : "roadmap_items JSON"
    ROADMAP_ITEM ||--o{ ROADMAP_ITEM : "parent_id self-ref"
```
