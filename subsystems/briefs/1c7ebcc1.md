TITLE: Signal Correlation and Anomaly Detection Engine
DESCRIPTION: A real-time subsystem that correlates incoming agent signals across temporal windows and applies statistical anomaly detection to flag degraded, stalled, or divergent agent behavior before cascading failures occur.
SUBSYSTEM: Ichor.Subsystems.SignalCorrelationEngine
SIGNAL_INTERFACE: Subscribes to :agent_heartbeat, :agent_event, :agent_status_changed, :run_started, :run_completed, :run_failed signals; emits :anomaly_detected, :correlation_alert, :signal_gap_detected
TOPIC: subsystem:signal_correlation_engine
VERSION: 0.1.0
FEATURES: sliding-window signal correlation, multi-agent event timeline reconstruction, z-score anomaly scoring, configurable alert thresholds, per-agent baseline modeling, signal gap detection, PubSub fan-out for downstream consumers
USE_CASES: detect stalled agents via heartbeat gap correlation, identify cascading failure chains by correlating run_failed sequences across teams, surface entropy spikes when agent event rates deviate from baseline, alert on temporal anomalies in pipeline execution order
ARCHITECTURE: GenServer holding a sliding ETS-backed ring buffer of recent signal events (configurable window, default 60s). On each incoming signal the engine updates the per-agent baseline model (exponential moving average + stddev), computes a z-score deviation, and emits anomaly signals when score exceeds threshold. A separate Timer process triggers periodic gap sweeps for agents with no recent heartbeat. Integrates with Ichor.Signals.Catalog for signal type resolution and Ichor.Registry for agent identity lookup.
DEPENDENCIES: Ichor.Registry, Ichor.Signals.Catalog, Ichor.Fleet.AgentProcess, Phoenix.PubSub
SIGNALS_EMITTED: :anomaly_detected, :correlation_alert, :signal_gap_detected, :baseline_updated
SIGNALS_SUBSCRIBED: :agent_heartbeat, :agent_event, :agent_status_changed, :run_started, :run_completed, :run_failed

---
Coordinator note: Brief synthesized directly by coordinator (run 1c7ebcc1). Researcher proposals were dispatched but no responses received before deadline. Synthesis draws on signal correlation + anomaly detection research domains assigned to both researchers.
