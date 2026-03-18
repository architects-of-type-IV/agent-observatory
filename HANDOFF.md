# ICHOR IV - Handoff

## Current Status: ichor_contracts Refactor Complete (2026-03-18)

### Session Summary

Major architectural refactor: extracted `ichor_contracts` shared library from the observatory host app. Subsystems now depend on a canonical contract surface instead of stubs. Signal system split into facade (contracts) + runtime (host) + Ash domain (host). All credo --strict issues resolved.

### Architecture

**ichor_contracts (subsystems/ichor_contracts/)**
- `Ichor.Signals` -- facade, dispatches to configured impl via `Application.get_env(:ichor_contracts, :signals_impl)`
- `Ichor.Signals.Behaviour` -- callback contract for signal implementations
- `Ichor.Signals.Noop` -- default no-op implementation (standalone compilation)
- `Ichor.Signals.Message` -- canonical envelope struct (owned here, not in host)
- `Ichor.Signals.Topics` -- pure topic string builder (owned here)
- `Ichor.Mes.Subsystem` -- behaviour (info/start/handle_signal/stop)
- `Ichor.Mes.Subsystem.Info` -- manifest struct
- `Ichor.PubSub` -- name atom stub
- `Phoenix.PubSub` -- conditional stub

**Host app (lib/ichor/)**
- `Ichor.Signals.Runtime` -- implements `Ichor.Signals.Behaviour`, owns PubSub transport, catalog validation
- `Ichor.Signals.Domain` -- Ash Domain, owns `Ichor.Signals.Event` resource
- `Ichor.Signals.Catalog` -- signal definitions (split into 5 bounded modules)
- `Ichor.Signals.Bus` -- PubSub broadcast
- `Ichor.Signals.Buffer` -- ETS signal buffer
- Config: `config :ichor_contracts, :signals_impl, Ichor.Signals.Runtime`
- Config: `ash_domains` uses `Ichor.Signals.Domain` (not `Ichor.Signals`)

**Subsystem build pipeline**
- `Mes.SubsystemScaffold` creates `subsystems/{name}/` with mix.exs (dep on ichor_contracts), README.md, integration.md
- Workers build inside `subsystems/{name}/` only -- never edit host files
- `Mes.CompletionHandler` reacts to `:dag_run_completed` -> `SubsystemLoader.compile_and_load`
- `SubsystemLoader` hot-loads only `Ichor.Subsystems.*` modules into BEAM

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN
- `mix dialyzer` -- CLEAN
- `mix credo --strict` -- 1 intentional FIXME only (was 17 issues before)
- `subsystems/ichor_contracts` -- compiles standalone
- `subsystems/pulse_monitor` -- compiles standalone against ichor_contracts

### What's Next
1. Press Build on PulseMonitor -- test the full pipeline with ichor_contracts
2. Catalog split for Dag.Prompts (260L -> per-role modules)
3. SwarmMonitor migration (deferred)
