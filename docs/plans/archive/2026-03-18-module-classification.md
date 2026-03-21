# Module Classification Inventory

This inventory classifies the current backend source tree into target apps and
target categories for the umbrella migration.

Categories:

- `pure_lib`: extract into reusable pure Elixir library apps
- `ash_domain`: move into an Ash domain app or domain-support namespace
- `runtime_shell`: keep in the product app as plain Elixir orchestration/runtime
- `web_product`: product-app bootstrapping, integration, or support code

The table is intentionally pattern-based so every current `lib/ichor/**/*.ex`
file is covered without duplicating 200+ rows.

## Root Modules

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/application.ex` | OTP boot and startup ordering | `ichor_app` | `web_product` | keep and rewrite to start umbrella children | supervisors, repo, endpoint | umbrella apps only |
| `lib/ichor/repo.ex` | Ecto repo | `ichor_app` | `web_product` | keep in product app initially | ecto, sqlite | repo users via domain apps |
| `lib/ichor/mailer.ex` | mail integration | `ichor_app` | `web_product` | keep | swoosh | unchanged |
| `lib/ichor/channels.ex` | product channel wiring | `ichor_app` | `web_product` | keep | PubSub, gateway | unchanged |
| `lib/ichor/core_supervisor.ex` | core runtime supervision | `ichor_app` | `runtime_shell` | keep and retarget children over time | notes, janitor, memory store, event buffer | extracted app contracts |
| `lib/ichor/gateway_supervisor.ex` | gateway supervision | `ichor_app` | `runtime_shell` | keep | gateway services | extracted app contracts |
| `lib/ichor/monitor_supervisor.ex` | monitors supervision | `ichor_app` | `runtime_shell` | keep | monitors, signals buffer | extracted app contracts |
| `lib/ichor/mesh_supervisor.ex` | mesh supervision | `ichor_app` | `runtime_shell` | keep, retarget to `ichor_mesh` contracts | causal DAG, topology, event bridge | product + `ichor_mesh` |
| `lib/ichor/activity.ex` | Ash domain root | `ichor_activity` | `ash_domain` | move and leave wrapper | activity resources | `ichor_activity` + pure libs |
| `lib/ichor/agent_tools.ex` | AshAi tool domain | `ichor_app` | `web_product` | keep as integration app/facade | memory, genesis, dag, fleet tools | domain apps + pure libs |
| `lib/ichor/archon.ex` | empty Ash domain placeholder | `ichor_app` | `web_product` | keep or remove after tool normalization | none | none |
| `lib/ichor/costs.ex` | Ash domain root | `ichor_costs` | `ash_domain` | move and leave wrapper | token usage | `ichor_costs` |
| `lib/ichor/dag.ex` | Ash domain root | `ichor_dag` | `ash_domain` | move and leave wrapper | run/job resources | `ichor_dag`, `ichor_dag_core` |
| `lib/ichor/events.ex` | Ash domain root | `ichor_events` | `ash_domain` | move and leave wrapper | event/session resources | `ichor_events` |
| `lib/ichor/fleet.ex` | Ash domain root | `ichor_fleet` | `ash_domain` | move and leave wrapper | fleet resources | `ichor_fleet`, `ichor_tmux_runtime` |
| `lib/ichor/genesis.ex` | Ash domain root | `ichor_genesis` | `ash_domain` | move and leave wrapper | genesis resources | `ichor_genesis`, `ichor_dag_core` |
| `lib/ichor/mes.ex` | Ash domain root | `ichor_mes` | `ash_domain` | move and leave wrapper | MES project resource | `ichor_mes` |
| `lib/ichor/workshop.ex` | Ash domain root | `ichor_workshop` | `ash_domain` | move and leave wrapper | workshop resources | `ichor_workshop` |
| `lib/ichor/map_helpers.ex` | shared helpers | `ichor_app` | `web_product` | keep until a real shared-support app is justified | used across app | unchanged |
| `lib/ichor/instruction_overlay.ex` | app-specific prompt/instruction policy | `ichor_app` | `runtime_shell` | keep | fleet, operator paths | product contracts |
| `lib/ichor/event_buffer.ex` | ETS-backed event runtime shell | `ichor_app` | `runtime_shell` | keep shell, extract pure pieces to libs later | ETS, gateway event shape | `ichor_events`, `ichor_signals` |
| `lib/ichor/event_janitor.ex` | event cleanup shell | `ichor_app` | `runtime_shell` | keep | event buffer | product contracts |
| `lib/ichor/heartbeat.ex` | runtime observer | `ichor_app` | `runtime_shell` | keep | signals/runtime | extracted signal contracts |
| `lib/ichor/memories_bridge.ex` | signal-to-memory bridge | `ichor_app` | `runtime_shell` | keep shell, depend on `ichor_memory_core` and memories client later | signals, memories client | product + pure libs |
| `lib/ichor/memory_store.ex` | app memory GenServer shell | `ichor_app` | `runtime_shell` | keep shell, delegate to `ichor_memory_core` | memory store submodules | `ichor_memory_core` |
| `lib/ichor/notes.ex` | ETS notes runtime store | `ichor_app` | `runtime_shell` | keep unless promoted to durable notes domain | ETS | unchanged or `ichor_notes` later |
| `lib/ichor/operator.ex` | operator delivery shell | `ichor_app` | `runtime_shell` | keep and retarget to extracted contracts | fleet, tmux, registry | `ichor_fleet`, `ichor_tmux_runtime` |
| `lib/ichor/task_manager.ex` | file-backed task store | `ichor_app` | `runtime_shell` | keep until replaced by domain or extracted storage lib | file system, JSON | product contracts |
| `lib/ichor/agent_spawner.ex` | compatibility facade | `ichor_app` | `runtime_shell` | keep temporarily | fleet lifecycle | `ichor_tmux_runtime` + product registration |
| `lib/ichor/protocol_tracker.ex` | observability runtime shell | `ichor_app` | `runtime_shell` | keep | AgentProcess, signals, PubSub | extracted signal/contracts |
| `lib/ichor/quality_gate.ex` | runtime gate enforcement | `ichor_app` | `runtime_shell` | keep and split collaborators later | operator, swarm monitor, tmux | product contracts |
| `lib/ichor/agent_monitor.ex` | agent health runtime shell | `ichor_app` | `runtime_shell` | keep and split collaborators later | fleet, task manager, tmux | product contracts |
| `lib/ichor/pane_monitor.ex` | tmux pane runtime shell | `ichor_app` | `runtime_shell` | keep and split collaborators later | fleet, tmux | `ichor_tmux_runtime` + product contracts |
| `lib/ichor/swarm_monitor.ex` | runtime orchestration shell | `ichor_app` | `runtime_shell` | keep | task state, health, discovery | extracted pure/domain contracts |
| `lib/ichor/nudge_escalator.ex` | runtime monitor | `ichor_app` | `runtime_shell` | keep | signals, fleet | product contracts |

## Activity

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/activity/**/*.ex` | activity resources, preparations, analysis | `ichor_activity` | `ash_domain` | move whole subtree, keep subnamespaces | Ash, event-derived read models | `ichor_activity`, `ichor_signals` |

## Agent Tools

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/agent_tools/**/*.ex` | MCP/AshAi integration over many contexts | `ichor_app` | `web_product` | keep as integration boundary and retarget dependencies | memory store, genesis, dag, fleet | extracted domain apps + pure libs |

## Archon

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/archon/chat.ex` | public chat facade | `ichor_app` | `runtime_shell` | keep | commands, turn runner | product collaborators |
| `lib/ichor/archon/chat/**/*.ex` | chat parsing/building/formatting collaborators | `ichor_app` | `runtime_shell` | keep in product app | tool domains, LangChain, memories client | product contracts |
| `lib/ichor/archon/memories_client.ex` | external memories HTTP adapter | `ichor_app` | `runtime_shell` | keep initially; later candidate shared adapter | Req, memories API | pure memory contracts later |
| `lib/ichor/archon/team_watchdog/**/*.ex` | runtime team watchdog | `ichor_app` | `runtime_shell` | keep | archon/fleet runtime | product contracts |
| `lib/ichor/archon/tools.ex` | Archon tool domain | `ichor_app` | `web_product` | keep as integration boundary | AshAi, Archon tool resources | domain apps + pure libs |
| `lib/ichor/archon/tools/**/*.ex` | Ash tool resources over fleet/events/mes/memory | `ichor_app` | `web_product` | keep and retarget | current top-level app modules | extracted domain apps + pure libs |

## Costs

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/costs/**/*.ex` | Ash resource and support logic | `ichor_costs` | `ash_domain` | move whole subtree | Ash, repo | `ichor_costs` |

## DAG

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/dag/graph.ex` | pure DAG graph logic | `ichor_dag_core` | `pure_lib` | move directly | pure Elixir | `ichor_dag_core` only |
| `lib/ichor/dag/validator.ex` | pure DAG validation | `ichor_dag_core` | `pure_lib` | move directly | pure Elixir | `ichor_dag_core` only |
| `lib/ichor/dag/loader.ex` | DAG load/import logic | `ichor_dag_core` | `pure_lib` | split persistence adapter if needed | JSONL, job/run types | `ichor_dag_core`, `ichor_dag` |
| `lib/ichor/dag/exporter.ex` | DAG export logic | `ichor_dag_core` | `pure_lib` | move directly | job/run types | `ichor_dag_core`, `ichor_dag` |
| `lib/ichor/dag/worker_groups.ex` | pure grouping helpers | `ichor_dag_core` | `pure_lib` | move directly | DAG job shapes | `ichor_dag_core` |
| `lib/ichor/dag/run.ex` | Ash resource | `ichor_dag` | `ash_domain` | move | Ash, repo | `ichor_dag`, `ichor_dag_core` |
| `lib/ichor/dag/job.ex` | Ash resource | `ichor_dag` | `ash_domain` | move | Ash, repo | `ichor_dag`, `ichor_dag_core` |
| `lib/ichor/dag/job/**/*.ex` | resource preparations | `ichor_dag` | `ash_domain` | move with resources | Ash query prep | `ichor_dag` |
| `lib/ichor/dag/run_process.ex` | runtime execution shell | `ichor_app` | `runtime_shell` | keep | DAG resources, spawner | `ichor_dag`, `ichor_dag_core` |
| `lib/ichor/dag/run_supervisor.ex` | runtime supervisor | `ichor_app` | `runtime_shell` | keep | run process | product contracts |
| `lib/ichor/dag/spawner.ex` | runtime launch shell | `ichor_app` | `runtime_shell` | keep, later retarget | tmux/fleet runtime | `ichor_tmux_runtime`, `ichor_dag` |
| `lib/ichor/dag/supervisor.ex` | runtime supervisor root | `ichor_app` | `runtime_shell` | keep | DAG runtime | product contracts |
| `lib/ichor/dag/health_checker.ex` | runtime/analysis helper | `ichor_app` | `runtime_shell` | keep until proven reusable | DAG resource/runtime | product contracts |
| `lib/ichor/dag/prompts.ex` | product prompt content | `ichor_app` | `runtime_shell` | keep | product UX/prompt policy | unchanged |

## Events

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/events/**/*.ex` | Ash event/session resources | `ichor_events` | `ash_domain` | move whole subtree | Ash, repo | `ichor_events`, `ichor_signals` |

## Fleet

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/fleet/agent.ex` | Ash resource | `ichor_fleet` | `ash_domain` | move | Ash, lifecycle, supervisor | `ichor_fleet`, `ichor_tmux_runtime` |
| `lib/ichor/fleet/team.ex` | Ash resource | `ichor_fleet` | `ash_domain` | move | Ash, supervisor | `ichor_fleet` |
| `lib/ichor/fleet/preparations/**/*.ex` | Ash resource preparations | `ichor_fleet` | `ash_domain` | move with resources | registry/runtime projections | `ichor_fleet` + product facades |
| `lib/ichor/fleet/queries.ex` | resource/query support | `ichor_fleet` | `ash_domain` | move with domain if still needed | Ash/resource views | `ichor_fleet` |
| `lib/ichor/fleet/lifecycle.ex` | lifecycle public shell | `ichor_app` | `runtime_shell` | keep as product shell and compatibility boundary | lifecycle collaborators | `ichor_tmux_runtime` + product registration |
| `lib/ichor/fleet/lifecycle/**/*.ex` | tmux/runtime generic launch contracts | `ichor_tmux_runtime` | `pure_lib` | move after product-specific registration is separated | tmux, registration, cleanup | `ichor_tmux_runtime` |
| `lib/ichor/fleet/agent_process.ex` | GenServer shell | `ichor_app` | `runtime_shell` | keep | delivery, mailbox, registry, lifecycle | `ichor_fleet`, `ichor_signals` |
| `lib/ichor/fleet/agent_process/**/*.ex` | runtime collaborators | `ichor_app` | `runtime_shell` | keep until a narrower reusable contract emerges | fleet process state | product contracts |
| `lib/ichor/fleet/fleet_supervisor.ex` | runtime supervisor | `ichor_app` | `runtime_shell` | keep | registry, agent process, team supervisor | product contracts |
| `lib/ichor/fleet/team_supervisor.ex` | runtime supervisor | `ichor_app` | `runtime_shell` | keep | registry, agent process | product contracts |
| `lib/ichor/fleet/host_registry.ex` | runtime registry | `ichor_app` | `runtime_shell` | keep | cluster/pg | product contracts |
| `lib/ichor/fleet/session_eviction.ex` | runtime cleanup | `ichor_app` | `runtime_shell` | keep | fleet runtime | product contracts |
| `lib/ichor/fleet/agent_health.ex` | runtime health helper | `ichor_app` | `runtime_shell` | keep | fleet runtime | product contracts |
| `lib/ichor/fleet/tmux_helpers.ex` | generic mapping helper | `ichor_tmux_runtime` | `pure_lib` | move | pure mapping logic | `ichor_tmux_runtime` |

## Gateway

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/gateway/router.ex` | central runtime router | `ichor_app` | `runtime_shell` | keep and split collaborators later | fleet runtime, protocol tracker, channels | product contracts |
| `lib/ichor/gateway/event_bridge.ex` | runtime bridge | `ichor_app` | `runtime_shell` | keep, depend on `ichor_mesh` contracts later | mesh, entropy tracker, signals | `ichor_mesh` + product |
| `lib/ichor/gateway/topology_builder.ex` | runtime publisher | `ichor_app` | `runtime_shell` | keep | mesh DAG, signals | `ichor_mesh` + product |
| `lib/ichor/gateway/hitl_relay.ex` | runtime pause/buffer shell | `ichor_app` | `runtime_shell` | keep | ETS, signals | product contracts |
| `lib/ichor/gateway/channels/**/*.ex` | delivery adapters | `ichor_app` | `runtime_shell` | keep initially; shared tmux parts later depend on `ichor_tmux_runtime` | tmux/webhook/mailbox | `ichor_tmux_runtime` + product |
| `lib/ichor/gateway/agent_registry/**/*.ex` | runtime registry contracts | `ichor_app` | `runtime_shell` | keep | fleet runtime | product contracts |
| `lib/ichor/gateway/capability_map.ex` | runtime mapping | `ichor_app` | `runtime_shell` | keep | gateway runtime | product contracts |
| `lib/ichor/gateway/channel.ex` | adapter behaviour | `ichor_app` | `runtime_shell` | keep or later move to tmux/runtime lib if generalized | channel adapters | product contracts |
| `lib/ichor/gateway/cron_*.ex` | runtime scheduling | `ichor_app` | `runtime_shell` | keep | gateway runtime | product contracts |
| `lib/ichor/gateway/entropy_tracker.ex` | runtime tracker | `ichor_app` | `runtime_shell` | keep | mesh/event runtime | product contracts |
| `lib/ichor/gateway/envelope.ex` | message contract | `ichor_app` | `runtime_shell` | keep initially | gateway runtime | product contracts |
| `lib/ichor/gateway/heartbeat_*.ex` | gateway persistence/runtime helpers | `ichor_app` | `runtime_shell` | keep unless `ichor_gateway` domain is introduced later | Ecto/runtime | product contracts |
| `lib/ichor/gateway/hitl_events.ex` | product audit integration | `ichor_app` | `runtime_shell` | keep | gateway runtime | product contracts |
| `lib/ichor/gateway/hitl_intervention_event.ex` | persisted gateway audit schema | `ichor_app` | `runtime_shell` | keep now; later candidate for `ichor_gateway` domain | Ecto | optional `ichor_gateway` later |
| `lib/ichor/gateway/output_capture.ex` | runtime capture shell | `ichor_app` | `runtime_shell` | keep | tmux/process runtime | product contracts |
| `lib/ichor/gateway/schema_interceptor.ex` | runtime validation | `ichor_app` | `runtime_shell` | keep | envelope/event runtime | product contracts |
| `lib/ichor/gateway/tmux_discovery.ex` | runtime discovery | `ichor_app` | `runtime_shell` | keep | tmux | `ichor_tmux_runtime` |
| `lib/ichor/gateway/webhook_*.ex` | runtime webhook delivery | `ichor_app` | `runtime_shell` | keep | HTTP delivery | product contracts |

## Genesis

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/genesis/*.ex` excluding `mode_runner`, `mode_spawner`, `run_process`, `supervisor`, `mode_prompts` | Ash resources and domain-level model code | `ichor_genesis` | `ash_domain` | move into domain app with `Genesis.Artifacts` and `Genesis.Roadmap` namespaces | Ash, repo, node relationships | `ichor_genesis`, `ichor_dag_core` |
| `lib/ichor/genesis/mode_prompts.ex` | prompt content | `ichor_app` | `runtime_shell` | keep | product prompt policy | unchanged |
| `lib/ichor/genesis/mode_runner.ex` | runtime orchestration | `ichor_app` | `runtime_shell` | keep | genesis resources, spawner | `ichor_genesis`, `ichor_tmux_runtime` |
| `lib/ichor/genesis/mode_spawner.ex` | runtime launch shell | `ichor_app` | `runtime_shell` | keep | tmux/runtime | `ichor_tmux_runtime` |
| `lib/ichor/genesis/run_process.ex` | runtime process shell | `ichor_app` | `runtime_shell` | keep | genesis resources, mode runner | `ichor_genesis` |
| `lib/ichor/genesis/supervisor.ex` | runtime supervisor | `ichor_app` | `runtime_shell` | keep | run process | product contracts |

## Memory Store

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/memory_store/blocks.ex` | pure block operations | `ichor_memory_core` | `pure_lib` | move | ETS access assumptions today | storage behavior + core types |
| `lib/ichor/memory_store/recall.ex` | recall transformations/search | `ichor_memory_core` | `pure_lib` | move | ETS/table helpers today | storage behavior + core types |
| `lib/ichor/memory_store/archival.ex` | archival transformations/search | `ichor_memory_core` | `pure_lib` | move | ETS/table helpers today | storage behavior + core types |
| `lib/ichor/memory_store/persistence.ex` | persistence adapter | `ichor_memory_core` | `pure_lib` | move after storage behavior is explicit | filesystem, JSON | storage adapter contract |
| `lib/ichor/memory_store/tables.ex` | table/path constants | `ichor_memory_core` | `pure_lib` | move and normalize into contract/config module | ETS/file paths | core config |
| `lib/ichor/memory_store/broadcast.ex` | runtime broadcast helper | `ichor_app` | `runtime_shell` | keep or move later if generic | signals/pubsub | product contracts |

## MES

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/mes/project.ex` | persisted MES Ash resource | `ichor_mes` | `ash_domain` | move | Ash, repo | `ichor_mes` |
| `lib/ichor/mes/research_store.ex` | persisted or semi-persistent research data support | `ichor_app` | `runtime_shell` | keep until a stable MES research boundary exists | MES runtime | product contracts |
| `lib/ichor/mes/research_context.ex` | prompt/research context formatter | `ichor_app` | `runtime_shell` | keep | product prompt policy | unchanged |
| `lib/ichor/mes/team_prompts.ex` | prompt content | `ichor_app` | `runtime_shell` | keep | MES prompt policy | unchanged |
| `lib/ichor/mes/team_spec_builder.ex` | runtime spec builder | `ichor_app` | `runtime_shell` | keep, later depend on `ichor_tmux_runtime` only | lifecycle specs, prompt builders | `ichor_tmux_runtime` + product |
| `lib/ichor/mes/team_lifecycle.ex` | runtime lifecycle shell | `ichor_app` | `runtime_shell` | keep | team cleanup, team launch | product contracts |
| `lib/ichor/mes/team_cleanup.ex` | runtime cleanup shell | `ichor_app` | `runtime_shell` | keep | lifecycle cleanup, run process | product contracts |
| `lib/ichor/mes/team_spawner.ex` | compatibility facade | `ichor_app` | `runtime_shell` | keep temporarily | team lifecycle | product contracts |
| `lib/ichor/mes/run_process.ex` | runtime process shell | `ichor_app` | `runtime_shell` | keep | team lifecycle, janitor | product contracts |
| `lib/ichor/mes/janitor.ex` | runtime janitor | `ichor_app` | `runtime_shell` | keep | run process, lifecycle | product contracts |
| `lib/ichor/mes/scheduler.ex` | runtime scheduler | `ichor_app` | `runtime_shell` | keep | run process, mes lifecycle | product contracts |
| `lib/ichor/mes/completion_handler.ex` | runtime completion flow | `ichor_app` | `runtime_shell` | keep | mes project/runtime | `ichor_mes` + product |
| `lib/ichor/mes/project_ingestor.ex` | runtime ingestion shell | `ichor_app` | `runtime_shell` | keep | MES project, operator/runtime | `ichor_mes` + product |
| `lib/ichor/mes/research_ingestor.ex` | runtime ingestion shell | `ichor_app` | `runtime_shell` | keep | research store/runtime | product contracts |
| `lib/ichor/mes/subsystem_*.ex` | runtime compile/load scaffolding | `ichor_app` | `runtime_shell` | keep | filesystem/build/runtime loading | product contracts |
| `lib/ichor/mes/supervisor.ex` | runtime supervisor | `ichor_app` | `runtime_shell` | keep | MES runtime services | product contracts |

## Mesh

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/mesh/decision_log.ex` | reusable schema/validation contract | `ichor_mesh` | `pure_lib` | move directly | Ecto embedded schemas | `ichor_mesh` |
| `lib/ichor/mesh/causal_dag.ex` | reusable DAG/session core with runtime shell aspects | `ichor_mesh` | `pure_lib` | move and keep generic runtime API; product-specific publishers stay outside | ETS, PubSub subscribe hook | `ichor_mesh`, `ichor_signals` |

## Signals

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/signals/catalog/**/*.ex` | signal catalog definitions | `ichor_signals` | `pure_lib` | move directly | pure data | `ichor_signals` |
| `lib/ichor/signals/buffer.ex` | runtime signal buffer | `ichor_signals` | `pure_lib` | move if kept generic, otherwise leave wrapper in product app | ETS, signal contracts | `ichor_signals` |
| `lib/ichor/signals/bus.ex` | signal bus runtime | `ichor_signals` | `pure_lib` | move directly | PubSub/runtime | `ichor_signals` |
| `lib/ichor/signals/runtime.ex` | runtime adapter | `ichor_signals` | `pure_lib` | move directly | signal contracts | `ichor_signals` |
| `lib/ichor/signals/from_ash.ex` | Ash notifier integration | `ichor_signals` | `pure_lib` | move directly | Ash notifier | `ichor_signals` + domain apps |
| `lib/ichor/signals/domain.ex` | Ash domain wrapper | `ichor_signals` | `pure_lib` | move with signal-facing Ash wrappers | Ash | `ichor_signals` |
| `lib/ichor/signals/event.ex` | signal-facing Ash resource | `ichor_signals` | `pure_lib` | move with signal-facing wrappers | Ash, signal buffer/catalog | `ichor_signals` |

## Swarm Monitor

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/swarm_monitor.ex` | runtime orchestration shell | `ichor_app` | `runtime_shell` | keep | analysis, health, task_state | product contracts |
| `lib/ichor/swarm_monitor/**/*.ex` | monitor collaborators | `ichor_app` | `runtime_shell` | keep until reusable contracts emerge | jq/file/task runtime | product contracts |

## Workshop

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/workshop/**/*.ex` | Ash resources and blueprint model support | `ichor_workshop` | `ash_domain` | move whole subtree with `Workshop.Blueprints` namespace | Ash, repo | `ichor_workshop`, `ichor_tmux_runtime` |

## Plugs

| Source Pattern | Current Role | Target App | Category | Move Strategy | Current Dependencies | Target Dependencies |
| --- | --- | --- | --- | --- | --- | --- |
| `lib/ichor/plugs/**/*.ex` | web/product plug code | `ichor_app` | `web_product` | keep | Phoenix | unchanged |

## Coverage Notes

This inventory intentionally covers the current backend by source pattern rather than
one row per file. The covered set is the current `lib/ichor/**/*.ex` tree, which at the
time of writing contains 207 backend source files grouped into these families:

- root: 35
- activity: 7
- agent_tools: 12
- archon: 21
- costs: 2
- dag: 14
- events: 2
- fleet: 25
- gateway: 24
- genesis: 17
- memory_store: 6
- mes: 18
- mesh: 2
- plugs: 1
- signals: 12
- swarm_monitor: 4
- workshop: 5

Any new module added during the migration must be classified into this same structure
before it is extracted.
