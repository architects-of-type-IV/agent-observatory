# BRAIN -- Session Knowledge

## AshSqlite Aggregate Limitation
AshSqlite's `can?/2` returns `false` for `{:aggregate_relationship, _}`. Aggregates block is NOT supported. Workaround: compute counts from fetched records.

## AshSqlite ALTER COLUMN Limitation
SQLite does not support ALTER COLUMN. Remove `modify` lines from auto-generated migrations for allow_nil? changes. Enforce at Ash level only.

## Ash Notifier Data Availability
Notifiers receive the result record and changeset. Data existing only as local variables in action bodies (e.g., newly-constructed embedded resource IDs) cannot be extracted without array diffing. Use TODO when this blocks notifier conversion.

## set_attribute vs attribute defaults
`set_attribute(:status, :pending)` in create is redundant when attribute has `default(:pending)`. Ash applies defaults automatically.

## require_atomic?(false) triggers
Only fn-based changes and function-capture changes require it. DSL builtins (`set_attribute`, `atomic_update`) are atomic-safe.

## jq Injection Prevention
Never interpolate external values into jq program strings. Use `--arg` flags: `["--arg", "tid", task_id, "--arg", "ow", new_owner]` with `$tid` / `$ow` in the jq expression.

## Shell Script Sanitization
Agent names flow into shell scripts via tmux. Always sanitize: `String.replace(name, ~r/[^a-zA-Z0-9_-]/, "")` and single-quote paths in shell scripts.

## Elixir 1.19 Typing and Dead Error Clauses
Elixir 1.19's type system flags `{:error, _}` clauses as "will never match" when the function spec only declares `{:ok, _}`. Use `try/rescue` instead of `case` when the function can only raise (not return error tuples) but you want graceful degradation.

## ETS Reads Outside GenServer
`:public` ETS reads from non-owning processes are safe for concurrent reads but may see partial state during concurrent writes. For snapshot consistency, route through `GenServer.call`. For best-effort, document the staleness risk.
