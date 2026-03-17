# Genesis Tab Design

**Date:** 2026-03-17

## Layout

New "Genesis" tab alongside Factory/Research in MES view. Full-width when active.

### Structure

```
[Factory] [Research] [Genesis]

Genesis tab:
  Node controls bar (mode buttons, gate check, generate DAG)
  Tab bar: [Decisions] [Requirements] [Checkpoints] [Roadmap]

  Each tab: master-detail
    Left (w-80): artifact list
    Right (flex-1): full rendered markdown content
```

### Tabs

- **Decisions**: ADRs. List shows code + title + status badge. Detail renders full ADR content as rich text.
- **Requirements**: Features + Use Cases. List shows code + title. Detail renders FRD/UC content.
- **Checkpoints**: Gate assessments + conversations. List shows title + mode. Detail renders content.
- **Roadmap**: Phases/Sections/Tasks/Subtasks. List shows hierarchy. Detail renders task content.

### Data Flow

- Assign: `@genesis_tab` (`:decisions`, `:requirements`, `:checkpoints`, `:roadmap`)
- Assign: `@genesis_selected` (`nil` or `{type, id}`)
- Event: `"genesis_select_tab"`, `"genesis_select_artifact"`
- Genesis node loaded with all associations (existing pattern)
- Subscribe to genesis signals for live artifact updates

### Content Rendering

Markdown rendered server-side to HTML. Artifacts are agent-produced, read-only. Full readable documents, not compressed summaries.
