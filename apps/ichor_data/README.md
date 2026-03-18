# ichor_data

Shared Ecto repository for the entire ICHOR umbrella. All SQLite persistence flows through
a single `Ichor.Repo` instance defined here.

## Ash Domains

None. This app defines no Ash domains or resources.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Repo` | `Ecto.Repo` backed by SQLite3 via `ecto_sqlite3`. OTP app is `:ichor_data`. |

## Dependencies

- `ecto_sql` -- Ecto SQL layer
- `ecto_sqlite3` -- SQLite adapter

## Architecture Role

`ichor_data` is the persistence foundation for the umbrella. Every sibling app that
persists to SQLite (events, fleet, workshop, MES, genesis, dag) declares `ichor_data`
as a dependency and configures its Ash resources to use `Ichor.Repo`.

Migrations live in `priv/repo/migrations/` within this app. Seeds are in
`priv/repo/seeds.exs` and referenced from the root `mix setup` alias.
