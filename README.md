# ICHOR IV

ICHOR IV is a Phoenix LiveView dashboard for orchestrating multi-agent Claude Code teams. The Architect (human user) designs agent teams in the Workshop, runs software development projects through the Factory, and observes the entire system via a reactive signal backbone. Each agent is a Claude Code instance running in a tmux window; ICHOR manages their lifecycle, routing, and coordination without the Architect having to touch a terminal.

## Architecture

The application follows a hexagonal design with six Ash Domains plus dedicated namespaces for fleet process management, use-case orchestration, and signal-driven projectors:

| Domain / Namespace | Path | Responsibility |
|--------------------|------|----------------|
| **Workshop** | `/workshop` | Design agent types, teams, spawn links, and comm rules. Compile and launch teams. |
| **Factory** | `/mes` | Turn project briefs into requirements via the MES planning pipeline. Track pipeline runs and tasks. |
| **Signals** | system-wide | Reactive GenStage backbone (ADR-026). All system events flow through a producer/consumer pipeline; all mandatory reactions are Oban jobs. |
| **Events** | system-wide | Append-only durable event log (`StoredEvent`). Ash notifier bridges Ash actions into the pipeline. |
| **Archon** | system-wide | App manager agent. Exposes management tool surface (memory, command manifest, signal-fed state). |
| **Settings** | `/settings` | Application-wide configuration: registered projects, git info, folder locations. |
| **Infrastructure** | I/O boundary | External adapters only: tmux, webhook, Memories API. Wrapped as Ash Resources with `:none` data layer for policy-ready, code-interface-callable access. No business logic. |
| **fleet/** | OTP layer | Live agent and team GenServers (`AgentProcess`, `TeamSupervisor`, `FleetSupervisor`). |
| **orchestration/** | use-case layer | Agent and team launch/cleanup orchestrators. Consumes fleet and infrastructure. |
| **projector/** | signal consumers | Signal-driven GenServer projectors that react to domain events (watchdogs, ingestors, dispatchers). |

### Signal Pipeline (ADR-026)

Ash actions emit events via the `FromAsh` notifier. Events flow through a GenStage pipeline: `Ingress` (producer) buffers them; `Router` (consumer) dispatches to per-topic `SignalProcess` accumulators. Signals are flushed to `ActionHandler`, which executes mandatory side effects (Oban jobs) and observational projections.

```
Ash action -> FromAsh notifier -> Ingress (GenStage producer)
                                         |
                                  Router (GenStage consumer)
                                         |
                              SignalProcess per {module, key}
                                         |
                               ActionHandler: flush signal
                                    /              \
                            Oban job inserted    PubSub broadcast
                            (mandatory effect)   (observational)
```

### Oban Workers

Twelve workers across five queues handle durable side effects: `MesTick` (cron, MES scheduler), `ScheduledJob`, `WebhookDeliveryWorker` (HTTP POST with backoff), `ArchiveRunWorker`, `ResetRunTasksWorker`, `DisbandTeamWorker`, `KillSessionWorker`, `HealthCheckWorker` (cron), `ProjectDiscoveryWorker` (cron, scans for `tasks.jsonl`), `OrphanSweepWorker` (cron), `PipelineReconcilerWorker` (cron, AD-8 safety net), and `PruneStoredEventsWorker` (cron daily, 7-day event retention).

### Frontend

The UI is a single Phoenix LiveView at `/` split into ~35 handler modules. A component library under `lib/ichor_web/components/` provides reusable Tailwind components organized into named namespaces (`signal_feed/`, `command_components/`, `primitives/`, `ui/`, etc.). Terminal panels use xterm.js for tmux output rendering.

## Prerequisites

- Elixir 1.19 / Erlang 27
- `tmux` (agents run in tmux sessions; required at runtime)
- PostgreSQL (database backend)
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

- `lib/ichor/` -- all application code, organized by domain. See [TREE.md](lib/ichor/TREE.md) for the annotated module tree (~160 .ex files).
- `lib/ichor_web/` -- Phoenix LiveView, controllers, and component library (~130 .ex/.heex files).
- `docs/architecture/` -- architecture decision records and domain specs. See [INDEX.md](docs/architecture/INDEX.md) for the recommended reading order.
- `docs/diagrams/` -- Mermaid architecture diagrams and database ERD.
- `contracts/ichor_contracts/` -- shared behaviour contracts (in transition to main app).
- `priv/repo/migrations/` -- Ash-generated PostgreSQL migrations.

## Key Concepts

See [docs/plans/GLOSSARY.md](docs/plans/GLOSSARY.md) for canonical definitions of overloaded terms. Words like Team, Agent, Run, Pipeline, Session, and Spawn mean different things depending on which domain you are reading. The glossary disambiguates each one.

Start with the architecture docs before reading code:

1. [decisions.md](docs/architecture/decisions.md) -- eight load-bearing design decisions (AD-1 through AD-8)
2. [GLOSSARY.md](docs/plans/GLOSSARY.md) -- canonical term definitions
3. [diagrams/architecture.md](docs/diagrams/architecture.md) -- domain map and signal flow diagrams
