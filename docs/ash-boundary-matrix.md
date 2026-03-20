# Ichor Boundary Matrix

This is the working boundary matrix for the current `lib/ichor` tree.

It answers one question per module:

- should this remain a top-level Ash resource
- should this become an embedded resource
- should this stay a runtime/support module
- should this collapse into a domain action/read/projection
- should this split
- or should it be deleted after refactor

## Legend

- `domain`: keep as a public domain boundary
- `resource`: keep as a top-level Ash resource
- `embedded`: keep, but only as an embedded resource
- `runtime`: keep as OTP/runtime/integration code, not a resource
- `action`: collapse into a domain action/read/calculation/aggregate
- `support`: keep as a private helper/value module
- `split`: current module is hiding multiple concepts and should be split
- `merge`: current module should be merged into a neighboring module
- `delete`: temporary shim or synthetic layer that should disappear
- `decide`: unresolved concept; do not name/finalize until ownership is clarified

## Top Level

| Module | Target | Notes |
| --- | --- | --- |
| `application.ex` | `runtime` | Real OTP entrypoint. |
| `agent_watchdog.ex` | `runtime` | Real fleet monitoring process; keep but move under fleet ownership. |
| `control.ex` | `domain` | Temporary domain shell for fleet/workshop area; replace current scope, not final naming. |
| `event_buffer.ex` | `delete` | Compatibility shim delegating elsewhere. |
| `memories_bridge.ex` | `runtime` | Integration process; not a domain noun. |
| `memory_store.ex` | `runtime` | Real service; not an Ash resource. |
| `notes.ex` | `support` | Dashboard note store; keep private unless it becomes a first-class feature. |
| `observation_supervisor.ex` | `runtime` | Supervisor, not domain surface. |
| `observability.ex` | `domain` | Temporary read-model domain shell; should own only read-side facts. |
| `projects.ex` | `domain` | Temporary factory/project-execution domain shell. |
| `protocol_tracker.ex` | `support` | Cross-protocol correlation helper/service; not a resource. |
| `quality_gate.ex` | `action` | Business operation; do not mint as entity. |
| `repo.ex` | `support` | Infrastructure. |
| `system_supervisor.ex` | `runtime` | Supervisor. |
| `tools.ex` | `delete` | Synthetic tool boundary; move tools to owning domains. |

## architecture/

| Module | Target | Notes |
| --- | --- | --- |
| `architecture/boundary_audit.ex` | `support` | Keep as architecture guardrail. |

## archon/

| Module | Target | Notes |
| --- | --- | --- |
| `archon/chat.ex` | `runtime` | Real integration surface; update to consume domain tools directly. |
| `archon/command_manifest.ex` | `support` | Private command metadata. |
| `archon/memories_client.ex` | `runtime` | External service client. |
| `archon/signal_manager.ex` | `runtime` | Stateful signal consumer; not a resource. |
| `archon/team_watchdog.ex` | `runtime` | Lifecycle monitor process. |

## control/

| Module | Target | Notes |
| --- | --- | --- |
| `control/agent.ex` | `resource` | Keep concept; current module mixes reads and runtime ops, which should be thinned. |
| `control/agent_process.ex` | `runtime` | Real process implementation. |
| `control/agent_type.ex` | `resource` | Keep concept; reusable workshop defaults are real. |
| `control/blueprint.ex` | `merge` | Frontend naming wrapper over the real team model; migrate this toward a `team` resource and keep compatibility only as long as needed. |
| `control/team.ex` | `resource` | Keep and strengthen; this should become the durable authored team model, not just a runtime projection. It likely needs a real child/member concept because per-team instructions layer over an agent type. |
| `control/blueprint_state.ex` | `delete` | Exists because blueprint internals are raw maps; should vanish after embedded modeling. |
| `control/fleet_supervisor.ex` | `runtime` | Supervisor. |
| `control/host_registry.ex` | `runtime` | Runtime registry. |
| `control/presets.ex` | `support` | Seed/preset data, not a domain entity. |
| `control/team_spec_builder.ex` | `merge` | Fold into the team-definition spawn action/build pipeline once blueprint modeling is fixed. |
| `control/tmux_helpers.ex` | `merge` | Private launcher support; should not stay top-level. |

## control/analysis/

| Module | Target | Notes |
| --- | --- | --- |
| `control/analysis/agent_health.ex` | `support` | Pure health analysis helper. |
| `control/analysis/queries.ex` | `action` | These should become explicit domain reads/projections. |
| `control/analysis/session_eviction.ex` | `merge` | UI/read-model concern; merge into observability projection layer. |

## control/lifecycle/

| Module | Target | Notes |
| --- | --- | --- |
| `control/lifecycle/agent_launch.ex` | `runtime` | Real launch orchestration. |
| `control/lifecycle/agent_spec.ex` | `support` | Runtime contract/value module. |
| `control/lifecycle/cleanup.ex` | `runtime` | Cleanup orchestration. |
| `control/lifecycle/registration.ex` | `merge` | Merge into launch/cleanup once ownership settles. |
| `control/lifecycle/team_launch.ex` | `runtime` | Real launch orchestration. |
| `control/lifecycle/team_spec.ex` | `support` | Runtime contract/value module. |
| `control/lifecycle/tmux_launcher.ex` | `runtime` | Real transport/runtime integration. |
| `control/lifecycle/tmux_script.ex` | `merge` | Private implementation detail of tmux launch. |

## control/types/

| Module | Target | Notes |
| --- | --- | --- |
| `control/types/health_status.ex` | `support` | Keep enum type. |

## control/views/preparations/

| Module | Target | Notes |
| --- | --- | --- |
| `control/views/preparations/load_agents.ex` | `delete` | Should be replaced by real read actions/projections. |
| `control/views/preparations/load_teams.ex` | `delete` | Same issue as above. |

## events/

| Module | Target | Notes |
| --- | --- | --- |
| `events/event.ex` | `support` | Value struct, not a persisted resource. |
| `events/runtime.ex` | `runtime` | Ephemeral event runtime/buffer; keep while observability projection exists. |

## gateway/

| Module | Target | Notes |
| --- | --- | --- |
| `gateway/channel.ex` | `support` | Transport behaviour. |
| `gateway/cron_job.ex` | `resource` | Keep persisted scheduled-work concept, but move under the owning operations boundary. |
| `gateway/cron_scheduler.ex` | `runtime` | Runtime scheduler. |
| `gateway/entropy_tracker.ex` | `runtime` | Runtime monitoring service. |
| `gateway/event_bridge.ex` | `runtime` | Bridge process; not a domain noun. |
| `gateway/hitl_intervention_event.ex` | `resource` | Keep audit concept; ownership belongs with read-model/audit area. |
| `gateway/hitl_relay.ex` | `runtime` | Real runtime gate. |
| `gateway/output_capture.ex` | `runtime` | Real output polling process. |
| `gateway/schema_interceptor.ex` | `runtime` | Inbound validation boundary. |
| `gateway/tmux_discovery.ex` | `runtime` | Discovery process. |
| `gateway/webhook_delivery.ex` | `resource` | Keep persisted delivery lifecycle concept; move to owning operational boundary. |
| `gateway/webhook_router.ex` | `runtime` | Delivery worker/router. |

## gateway/agent_registry/

| Module | Target | Notes |
| --- | --- | --- |
| `gateway/agent_registry/agent_entry.ex` | `support` | Value-shaping helper, not a public concept. |

## gateway/channels/

| Module | Target | Notes |
| --- | --- | --- |
| `gateway/channels/ansi_utils.ex` | `support` | Private helper. |
| `gateway/channels/mailbox_adapter.ex` | `runtime` | Adapter implementation. |
| `gateway/channels/ssh_tmux.ex` | `runtime` | Adapter implementation. |
| `gateway/channels/tmux.ex` | `runtime` | Adapter implementation. |
| `gateway/channels/webhook_adapter.ex` | `runtime` | Adapter implementation. |

## mesh/

| Module | Target | Notes |
| --- | --- | --- |
| `mesh/causal_dag.ex` | `runtime` | In-memory causal graph service. |
| `mesh/decision_log.ex` | `embedded` | Good embedded-resource candidate. |
| `mesh/decision_log/helpers.ex` | `merge` | Private helper for embedded decision log. |

## memory_store/

| Module | Target | Notes |
| --- | --- | --- |
| `memory_store/persistence.ex` | `merge` | Private implementation of memory store. |
| `memory_store/storage.ex` | `merge` | Private implementation of memory store. |

## messages/

| Module | Target | Notes |
| --- | --- | --- |
| `messages/bus.ex` | `runtime` | Real messaging authority/service. |

## observability/

| Module | Target | Notes |
| --- | --- | --- |
| `observability/error.ex` | `resource` | Keep durable/queryable error concept. |
| `observability/event.ex` | `resource` | Keep durable event concept. |
| `observability/janitor.ex` | `runtime` | Retention/cleanup process. |
| `observability/message.ex` | `resource` | Keep read-model message concept if the dashboard continues to depend on it. |
| `observability/session.ex` | `resource` | Keep session concept. |
| `observability/task.ex` | `decide` | Likely projection smell; keep only if there is a true task read model separate from execution jobs. |

## observability/preparations/

| Module | Target | Notes |
| --- | --- | --- |
| `observability/preparations/event_buffer_reader.ex` | `delete` | Shim around missing ownership. |
| `observability/preparations/load_errors.ex` | `delete` | Should become real read/projected data shape. |
| `observability/preparations/load_messages.ex` | `delete` | Same. |
| `observability/preparations/load_tasks.ex` | `delete` | Same. |

## plugs/

| Module | Target | Notes |
| --- | --- | --- |
| `plugs/operator_auth.ex` | `support` | Keep as web boundary/infrastructure. |

## projects/

| Module | Target | Notes |
| --- | --- | --- |
| `projects/artifact.ex` | `split` | Too many concepts behind `kind`; likely over-collapsed. |
| `projects/completion_handler.ex` | `action` | Business reaction after completion, not an entity. |
| `projects/dag_generator.ex` | `action` | Generation operation, not a durable noun. |
| `projects/dag_prompts.ex` | `merge` | Fold into one prompt library module. |
| `projects/date_utils.ex` | `merge` | Private utility. |
| `projects/graph.ex` | `support` | Pure graph logic; keep private. |
| `projects/janitor.ex` | `runtime` | Runtime cleanup process. |
| `projects/lifecycle_supervisor.ex` | `runtime` | Supervisor. |
| `projects/mode_prompts.ex` | `merge` | Fold into one prompt library module. |
| `projects/node.ex` | `merge` | Strong collapse candidate into the MES project resource if `genesis`/`node` is only a pet name for the same project lifecycle object. |
| `projects/pipeline_stage.ex` | `action` | Stage derivation should be a calculation/read helper, not a standalone domain concept. |
| `projects/project.ex` | `resource` | Keep top-level project/subsystem brief concept. |
| `projects/project_ingestor.ex` | `runtime` | Intake/integration process. |
| `projects/research_context.ex` | `support` | Prompt/input shaping helper. |
| `projects/research_ingestor.ex` | `runtime` | Integration process. |
| `projects/research_store.ex` | `runtime` | External read interface; not a resource. |
| `projects/roadmap_item.ex` | `decide` | This unification may be acceptable in part; do not split blindly. |
| `projects/run.ex` | `resource` | Keep execution run concept. |
| `projects/runner.ex` | `runtime` | Real run lifecycle process; keep but shrink. |
| `projects/runtime.ex` | `split` | This is multiple responsibilities forced into one GenServer. |
| `projects/scheduler.ex` | `runtime` | Real scheduler. |
| `projects/spawn.ex` | `delete` | God-module orchestration surface; distribute into runtime/actions. |
| `projects/subsystem_loader.ex` | `runtime` | Runtime load operation. |
| `projects/subsystem_scaffold.ex` | `action` | Build/scaffold operation, not entity. |
| `projects/team_prompts.ex` | `merge` | Fold into one prompt library module. |
| `projects/team_spec.ex` | `merge` | This is assembly/orchestration code and should merge into runtime build pipeline. |
| `projects/job.ex` | `resource` | Keep execution job concept. |

## projects/job/changes/

| Module | Target | Notes |
| --- | --- | --- |
| `projects/job/changes/sync_run_process.ex` | `delete` | Cross-runtime mutation hook; replace with notifier/runtime subscription or move into orchestration layer. |

## projects/job/preparations/

| Module | Target | Notes |
| --- | --- | --- |
| `projects/job/preparations/filter_available.ex` | `action` | Availability logic belongs in read/action logic, not as a leftover preparation module. |

## projects/types/

| Module | Target | Notes |
| --- | --- | --- |
| `projects/types/work_status.ex` | `support` | Keep enum type. |

## signals/

| Module | Target | Notes |
| --- | --- | --- |
| `signals/buffer.ex` | `runtime` | Real signal buffer/feed service. |
| `signals/catalog.ex` | `support` | Keep as source of truth; may stay a module rather than resource. |
| `signals/event.ex` | `decide` | Keep only if an action-only resource is still the cleanest public surface for signal ops. |
| `signals/from_ash.ex` | `support` | Keep as notifier bridge, but stop centralizing everything here. |
| `signals/runtime.ex` | `runtime` | Real transport implementation. |

## tools/

| Module | Target | Notes |
| --- | --- | --- |
| `tools/agent_memory.ex` | `delete` | Synthetic MCP wrapper; move the surviving actions to the owning memory boundary. |
| `tools/genesis.ex` | `delete` | Synthetic MCP wrapper over planning/build concepts. |
| `tools/profiles.ex` | `delete` | Synthetic exposure/profile layer tied to `tools/` boundary. |
| `tools/project_execution.ex` | `delete` | Giant wrapper around real project/run/job concepts. |
| `tools/runtime_ops.ex` | `delete` | Giant wrapper around fleet/runtime operations. |

## tools/archon/

| Module | Target | Notes |
| --- | --- | --- |
| `tools/archon/memory.ex` | `delete` | Synthetic wrapper; keep capability, not this boundary. |

## tasks/

| Module | Target | Notes |
| --- | --- | --- |
| `tasks/board.ex` | `resource` | Tasks are created from MES specs and become DAG work; this is a real domain concept, though its final module location may move into the project/factory area. |
| `tasks/jsonl_store.ex` | `action` | `tasks.jsonl` sync boundary for multi-repo/cwd workflows; file sync helper, not a domain noun. |

## Recommended First Pass

These are the highest-value changes because they delete entire categories of accidental structure.

### Delete

- `tools.ex`
- `tools/*`
- `event_buffer.ex`
- `control/blueprint_state.ex`
- `control/views/preparations/*`
- `observability/preparations/*`
- `projects/spawn.ex`
- `projects/job/changes/sync_run_process.ex`

### Keep but thin

- `control/agent.ex`
- `control/team.ex`
- `control/blueprint.ex`
- `projects/project.ex`
- `projects/node.ex`
- `projects/run.ex`
- `projects/job.ex`
- `observability/event.ex`
- `observability/session.ex`
- `observability/message.ex`
- `observability/error.ex`

### Keep as real runtime

- supervisors
- runners
- schedulers
- relays
- bridges
- tmux/channel adapters

### Model properly

- blueprint nested state as embedded resources
- signal publication close to ownership
- dashboard reads as explicit domain reads/projections

## What This Reveals

The code is not mainly tangled because there are many concepts.

It is tangled because too many implementation modules were allowed to masquerade as domain boundaries:

- synthetic tools
- giant orchestration surfaces
- shim preparations
- kind-based pseudo-entities

Once those are removed, the remaining named things are much clearer:

- a small set of real resources
- a small set of real runtime services
- a larger set of logic that should never have received its own public name
