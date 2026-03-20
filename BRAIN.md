# BRAIN - What I've Learned

## Pattern: Collapsing Parallel Builders into One Module

When 3 modules share the same call structure (apply preset, build roster, build prompt map, call WorkshopBuilder.build_from_state), they collapse cleanly into one module with a dispatch atom as the first argument. The key is: **per-mode differences are data, not separate modules**.

## Pattern: Embedded JSON vs has_many for Co-Loaded Children (2026-03-20)

When child records are always loaded together, written together, and never queried independently, `{:array, :map}` embedded JSON is better than has_many + separate tables:
- No joins, no relationship loading, single-row reads/writes
- Simpler resource (no manage_relationship changes, no direct_control)
- Migration: `create table` + `flush()` (DDL must commit before DML), raw SQL data migration, then `DROP TABLE IF EXISTS` for old tables

## Ash `{:array, :map}` Key Behavior

- SQLite stores as JSON TEXT; on load, maps come back **string-keyed**
- Write time: atom or string keys both accepted
- Read time: always string keys -- use `Map.get(map, "key")` not `map.key`
- Keep a clear boundary: canvas state = atom keys, persisted maps = string keys

## Migration Infrastructure

- `mix ash.codegen` with no prior snapshots generates bad "create all" migration -- write manual migrations only
- `flush()` is required between DDL (`create table`) and DML (`repo().query!`) in Ecto migrations
- `repo()` is available in migration modules for raw SQL data migrations
- SQLite FK drop: not supported via ALTER TABLE; just `DROP TABLE IF EXISTS` child tables before parent
