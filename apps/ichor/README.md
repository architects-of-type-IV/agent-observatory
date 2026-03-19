# ichor

The main Phoenix web application and runtime orchestration hub for the ICHOR system.

## Ash Domains

This app does not define Ash Domains of its own. It depends on all sibling apps and wires their
domains into a unified runtime. The gateway, fleet, DAG, MES, and Genesis subsystems are
all orchestrated from this app.

## Key Modules

| Module | Responsibility |
|---|---|
| `Ichor.Application` | OTP application entry point, supervision tree root |
| `IchorWeb.Router` | Phoenix route definitions for all HTTP and LiveView endpoints |
| `IchorWeb.DashboardLive` | Primary operator LiveView, split across ~30 handler modules |
| `Ichor.Gateway.*` | Inbound message routing, heartbeat management, HITL relay, tmux discovery |
| `Ichor.Fleet.*` | Runtime agent/team lifecycle, comms, session eviction, health analysis |
| `Ichor.Archon.*` | AI operator assistant: LLM chat chain, command registry, signal reactions |
| `Ichor.Mes.*` | MES runtime: team spawning, scheduler, subsystem loader, run process |
| `Ichor.Dag.*` | DAG runtime: spawner, run supervisor, worker groups, runtime event bridge |
| `Ichor.Genesis.*` | Genesis pipeline runtime: mode runner, spawner, DAG generator |
| `Ichor.ObservationSupervisor` | Supervises gateway observation infrastructure: event bridge, topology projection, causal DAG |
| `Ichor.AgentTools.*` | MCP tool implementations served to agents (inbox, memory, spawn, tasks) |
| `IchorWeb.Components.*` | Phoenix component library for all dashboard views |
| `Ichor.Fleet.Overseer` | Runtime oversight and aggregated DAG/fleet operational state |

## Dependencies on Other Apps

Depends on all umbrella siblings:
- `ichor_data` -- shared Ecto Repo (SQLite)
- `ichor_signals` -- PubSub transport and signal catalog
- `ichor_fleet` -- Agent/Team Ash domain
- `ichor_dag` -- DAG Run/Job Ash domain
- `ichor_tmux_runtime` -- tmux session and window lifecycle
- `ichor_contracts` -- shared Signals behaviour contract

## Architecture Role

`ichor` is the composition root. It owns no Ash resources but consumes all domain APIs.
All Phoenix HTTP/LiveView surface, gateway ingestion, observation supervision,
and runtime supervisors live here. Sibling apps are focused domain or infrastructure
libraries; this app wires them into a running system.
