# ICHOR IV - Brain

## Identity
- **ICHOR IV**: sovereign control plane for autonomous agents
- **Architect**: the user. **Archon**: AI floor manager. **Operator**: messaging relay.

## Signal-First Architecture (2026-03-19, CRITICAL)
Every meaningful action MUST emit a Signal. The Signals stream is the nervous system.
- 37 actions currently bypass Signals (audit complete, wiring pending)
- `Ichor.Channels` is a shadow PubSub layer -- needs signal emission or deprecation
- `genesis_artifact_created` exists in catalog but is NEVER emitted
- DAG run lifecycle (create/complete/fail) is invisible to Signals

## MessageRouter (2026-03-19, IMPLEMENTED)
- Single `send/1` API. Plain module (Iron Law: no process).
- Replaces: Fleet.Comms, Tools.Messaging, Operator.send
- All 14 callers go through MessageRouter directly
- ETS message log + :fleet_changed signal in one path

## ichor_contracts (2026-03-18, IMPLEMENTED)
- Facade + behaviour + config dispatch for Ichor.Signals
- Host configures `:signals_impl` -> `Ichor.Signals.Runtime`
- Subsystems depend on ichor_contracts, never on host

## Ash AI Patterns (2026-03-19, REFERENCE)
- Ash constraint system is primary for LLM type exposure, not @spec
- Action `description` strings are load-bearing for MCP tool manifests
- `Ash.Type.NewType` for structured LLM output
- Tools declared at Domain level via `tools do` DSL block
- Authorization flows through Ash actor policies automatically

## Critical Constraints
- Module limit: 200L guide, SRP is the real rule. One module per file.
- Pattern matching, no if/else. Dispatch params first, unused last.
- Ash Domain is canonical API. No direct resource access.
- No decorative banners. @doc and module structure for organization.
- @spec required on public API functions. Skip GenServer callbacks.
- credo --strict must be clean. Zero warnings.

## User Preferences
- "Always go for pragmatism"
- "Architect solutions with agents before coding"
- "Take ownership" = fix ALL issues including pre-existing
- "Use codex actively as sparring partner"
- "Function names generic, focus on input/output shapes"
- "All messages through Signals first"
- "Use multiple agents for research and review"
