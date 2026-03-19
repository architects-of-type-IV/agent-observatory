TITLE: EchoSuppressor — Semantic Deduplication Engine
DESCRIPTION: Detects redundant agent work by fingerprinting incoming task descriptions against a rolling ETS cache of recent completions, routing duplicates directly to cached results instead of spawning new agents. Cuts wasteful re-execution in high-throughput MES pipelines where multiple coordinators independently discover the same subproblems.
SUBSYSTEM: Ichor.Subsystems.EchoSuppressor
SIGNAL_INTERFACE: Subscribes to agent:dispatched and mes:task_started; emits echo:suppressed and echo:cache_miss
TOPIC: subsystem:echo_suppressor
VERSION: 0.1.0
FEATURES: rolling ETS fingerprint cache with TTL, semantic similarity hashing via simhash of task description tokens, configurable suppression threshold, cache-hit routing back to original requestor, signal emission for all decisions, per-pipeline and global suppression modes, optional dry-run mode for observation without suppression
USE_CASES: high-throughput MES runs where coordinators issue overlapping research tasks, fleet pipelines where multiple agents independently discover the same subproblem, DAG execution where upstream retries duplicate already-completed downstream work, cost reduction by avoiding redundant LLM calls for semantically identical prompts
ARCHITECTURE: GenServer holding ETS table keyed by simhash of normalized task text; subscribes to PubSub topic agent:dispatched via Ichor.Observability; on each event computes simhash, checks ETS for matches within Hamming distance threshold, emits echo:suppressed signal with cached result reference if match found or echo:cache_miss if novel, stores result fingerprint on mes:task_completed events; TTL enforced by :erlang.send_after sweep; exposes read-only ETS for dashboard introspection
DEPENDENCIES: Ichor.Observability, Ichor.Gateway.EntropyTracker, Ichor.Fleet.AgentProcess, Ichor.Mesh.CausalDag
SIGNALS_EMITTED: echo_suppressed, echo_cache_miss, echo_cache_evicted, echo_suppressor_started
SIGNALS_SUBSCRIBED: agent_dispatched, mes_task_started, mes_task_completed, dag_node_started
