# ichor_data Refactor Analysis

## Overview

Single-purpose app: owns the Ecto Repo. 1 file, 7 lines. No refactoring needed.

---

## Module Inventory

| Module | File | Lines | Type | Purpose |
|--------|------|-------|------|---------|
| `Ichor.Repo` | ichor/repo.ex | 7 | Other | AshSqlite.Repo for SQLite data layer |

---

## Cross-References

### Called by
All Ash resources with `AshSqlite.DataLayer` use `Ichor.Repo`. Referenced in:
- `Ichor.Dag.Run`
- `Ichor.Dag.Job`
- `Ichor.Events.Event`
- `Ichor.Events.Session`
- `Ichor.Fleet.Agent` (if persisted)
- `Ichor.Genesis.*` resources
- `Ichor.Mes.Project`
- `Ichor.Workshop.*` resources

### Calls out to
None. Pure configuration module.

---

## Boundary Violations

None.

---

## Consolidation Plan

None needed. This app exists solely as the canonical Repo owner to avoid circular dependencies.

---

## Priority

No action required.
