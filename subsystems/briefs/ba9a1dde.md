TITLE: Adaptive Signal Mesh
DESCRIPTION: A unified subsystem that correlates signals across the agent fleet and dynamically redistributes load based on real-time capacity and pattern data. Combines sliding-window event correlation with EWMA-based load balancing to give Ichor coordinated awareness of fleet health and autonomous rebalancing capability.
SUBSYSTEM: Ichor.Subsystems.AdaptiveSignalMesh
SIGNAL_INTERFACE: Subscribes to agent:signal:*, fleet:event:*, fleet:agent:metrics, agent:queue:depth, agent:latency:p99, gateway:entropy_alerts
TOPIC: subsystem:adaptive_signal_mesh
VERSION: 0.1.0
FEATURES: sliding-window cross-agent signal correlation, EWMA load smoothing, weighted least-connections routing, hysteresis threshold guards, ETS ring buffer per agent, PubSub-driven mesh topology
USE_CASES: detect coordinated agent failure cascades, shed load from saturated agents before queue overflow, surface causal signal chains in the dashboard, auto-rebalance task assignment during fleet scaling events
ARCHITECTURE: GenServer core with ETS ring buffer table per registered agent; correlation pass runs on every signal ingestion via handle_cast; load pass runs on configurable tick (default 500ms); emits signals via Phoenix.PubSub; supervised under Ichor.Gateway.GatewaySupervisor
DEPENDENCIES: Ichor.Registry, Ichor.Gateway.EventBridge, Ichor.Gateway.EntropyTracker, Phoenix.PubSub
SIGNALS_EMITTED: correlation_match, correlation_anomaly, balancer_rebalance, balancer_shed_load, balancer_agent_saturated
SIGNALS_SUBSCRIBED: agent_signal, fleet_event, fleet_agent_metrics, agent_queue_depth, agent_latency_p99, entropy_alert
