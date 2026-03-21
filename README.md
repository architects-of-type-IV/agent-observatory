# ICHOR IV

ICHOR IV is a Phoenix LiveView dashboard for orchestrating multi-agent Claude Code teams. The Architect (human user) designs agent teams in the Workshop, runs software development projects through the Factory, and observes the entire system via a reactive signal backbone. Each agent is a Claude Code instance running in a tmux window; ICHOR manages their lifecycle, routing, and coordination without the Architect having to touch a terminal.

## Architecture

The application is organized into five Ash Domains:

| Domain | Path | Responsibility |
|--------|------|----------------|
| **Workshop** | `/workshop` | Design agent types, teams, spawn links, and comm rules. Compile and launch teams. |
| **Factory** | `/mes` | Turn project briefs into requirements via the MES planning pipeline. Track pipeline runs and tasks. |
| **SignalBus** | system-wide | Reactive pub/sub backbone. All system events are signals; all mandatory reactions are Oban jobs. |
| **Archon** | system-wide | App manager agent. Exposes management tool surface (memory, command manifest, signal-fed state). |
| **Infrastructure** | host layer | Supervisors, registry, tmux adapters, TeamLaunch, agent processes. No business logic. |

### Signal Flow

Ash actions emit signals via `Ichor.Signals.Runtime` (PubSub broadcast). Subscribers receive signals and decide whether to act. For observational purposes, subscribers read and update state. For mandatory side effects (cleanup, archival, session teardown), subscribers insert Oban jobs rather than acting inline. This keeps the reactive path reliable across restarts.

```
Ash action -> Signal emitted -> PubSub broadcast
                                     |
                              Subscribers receive
                                     |
                    observational    |    mandatory
                    (read state)     |    (insert Oban job)
                                     |
                              Oban worker runs
```

### Oban Workers

Eleven workers across five queues handle durable side effects: `MesTick` (cron, MES scheduler), `ScheduledJob`, `WebhookDeliveryWorker` (HTTP POST with backoff), `ArchiveRunWorker`, `ResetRunTasksWorker`, `DisbandTeamWorker`, `KillSessionWorker`, `HealthCheckWorker` (cron), `ProjectDiscoveryWorker` (cron, scans for `tasks.jsonl`), `OrphanSweepWorker` (cron), and `PipelineReconcilerWorker` (cron, AD-8 safety net).

## Prerequisites

- Elixir 1.19 / Erlang 27
- `tmux` (agents run in tmux sessions; required at runtime)
- SQLite (no external database needed)
- Node.js (for asset compilation via esbuild and Tailwind)

## Setup

```bash
mix deps.get
mix ash.setup       # creates DB, runs migrations, seeds
mix phx.server      # starts on http://localhost:4005
```

For a full asset rebuild:

```bash
mix assets.build
```

To reset the database:

```bash
mix ecto.reset
```

## Project Structure

- `lib/ichor/` -- all application code, organized by domain. See [TREE.md](lib/ichor/TREE.md) for the annotated module tree.
- `docs/architecture/` -- architecture decision records and domain specs. See [INDEX.md](docs/architecture/INDEX.md) for the recommended reading order.
- `docs/diagrams/` -- Mermaid architecture diagrams and database ERD.
- `contracts/ichor_contracts/` -- shared behaviour contracts (in transition to main app).
- `priv/repo/migrations/` -- Ash-generated SQLite migrations.

## Key Concepts

See [docs/plans/GLOSSARY.md](docs/plans/GLOSSARY.md) for canonical definitions of overloaded terms. Words like Team, Agent, Run, Pipeline, Session, and Spawn mean different things depending on which domain you are reading. The glossary disambiguates each one.

Start with the architecture docs before reading code:

1. [decisions.md](docs/architecture/decisions.md) -- eight load-bearing design decisions (AD-1 through AD-8)
2. [GLOSSARY.md](docs/plans/GLOSSARY.md) -- canonical term definitions
3. [diagrams/architecture.md](docs/diagrams/architecture.md) -- domain map and signal flow diagrams
