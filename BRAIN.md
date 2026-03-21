# BRAIN -- Session Knowledge

## spawn/1 Is Generic
`spawn("team-name")` = look up Workshop design -> compile to TeamSpec -> TeamLaunch. The current `:mes`, `:pipeline`, `:planning` atoms are team configurations, not architectural spawn modes. In the target state, there's no special-case code per kind -- just team names with Workshop-configured prompts.

## Constraints Are Pattern Matches
A subscriber that checks "is mes already running?" is just a `handle_info` clause that pattern-matches on team name. No Policy module, no abstraction. Elixir pattern matching IS the mechanism.

## Don't Name What Elixir Already Has
Before creating a new module or concept, ask "is this just a function clause?" If yes, it stays unnamed in code. Concepts can exist in conversation without becoming modules. OOP creep happens through premature naming.

## Signals Is the Decoupling Mechanism
Cross-domain calls should be: emit signal -> subscriber reacts. Not: module A calls module B directly. Adding behavior = adding a subscriber, not editing an existing module.

## AshSqlite Limitations
- No aggregates (can?/2 returns false for aggregate_relationship)
- No ALTER COLUMN (modify in migrations fails)
- Enforce constraints at Ash level, remove column-modify from generated migrations

## Notifier Data Availability
Notifiers only see the result record + changeset. Locally-scoped data (embedded resource IDs constructed in action body) can't be extracted without array diffing.

## set_attribute vs Attribute Defaults
Redundant in create actions. Ash applies defaults automatically.

## require_atomic?(false) Triggers
Only fn-based changes and function-capture changes need it. DSL builtins are atomic-safe.

## jq Injection Prevention
Never interpolate into jq program strings. Use --arg flags with $variable references.

## Shell Script Sanitization
Agent names flow into shell scripts. Sanitize with regex, single-quote paths.

## Elixir 1.19 Typing
Flags {:error, _} clauses as "will never match" when function spec only declares {:ok, _}. Use try/rescue for graceful degradation.
