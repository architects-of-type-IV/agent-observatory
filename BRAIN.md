# BRAIN -- Session Knowledge

## AshSqlite Aggregate Limitation
AshSqlite's `can?/2` returns `false` for `{:aggregate_relationship, _}`. The `aggregates do count end` block is NOT supported by the SQLite data layer. Workaround: compute counts from fetched records in the action's run function.

## AshSqlite ALTER COLUMN Limitation
SQLite does not support ALTER COLUMN. Migrations that add NOT NULL constraints to existing columns via `modify :col, :type, null: false` will fail with `(ArgumentError) ALTER COLUMN not supported by SQLite3`. For `allow_nil?(false)` on existing attributes, either: (1) remove the modify from the migration (enforce at Ash level only), or (2) recreate the table.

## Ash Notifier Data Availability
When converting `Signals.emit` from action bodies to notifiers, the notification only contains the result record and changeset. If the signal needs data that exists only as local variables in the action body (e.g., a newly-constructed embedded resource's ID before it's persisted as part of an array), the notifier cannot extract it without diffing arrays. Use TODO + comment when this happens.

## Inline Pattern (Control Wrappers)
When inlining a module that is itself used by another module being inlined, handle the dependency chain in the right order: inline the leaf first, then the intermediate.

## format hook / alias sorting side-effect
The mix format hook re-sorts aliases alphabetically when it fires after an Edit. Trust the file state after hook fires.

## set_attribute with MFA vs attribute defaults
`set_attribute(:status, :pending)` in a create action is redundant when the attribute already has `default(:pending)`. Ash applies attribute defaults automatically. Only use `set_attribute` in create actions when the value differs from the default or is dynamic.

## require_atomic?(false) triggers
Only fn-based changes (`change fn changeset, _ ->`) and function-capture changes (`set_attribute(:field, &Module.fun/0)`) require `require_atomic?(false)`. DSL builtins like `set_attribute(:field, value)` and `atomic_update` are atomic-safe.
