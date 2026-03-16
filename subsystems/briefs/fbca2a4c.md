TITLE: Adaptive Process Intelligence
DESCRIPTION: A unified MES subsystem combining real-time sensor anomaly detection via hybrid CUSUM-EWMA with Shannon entropy monitoring of fleet-wide anomaly distributions, enabling both per-sensor spike detection and macro-level disorder prevention across the manufacturing fleet.
SUBSYSTEM: Ichor.Subsystems.AdaptiveProcessIntelligence
SIGNAL_INTERFACE: Subscribes to [:mes, :sensor, :reading] for raw sensor readings and {:fleet_heartbeat, snapshot} for agent state snapshots; emits corrective signals and anomaly alerts through Ichor.Signals PubSub bus
TOPIC: subsystem:adaptive_process_intelligence
VERSION: 0.1.0
FEATURES: hybrid CUSUM-EWMA anomaly detection per sensor, Shannon entropy monitoring over fleet anomaly distribution, bidirectional shift detection (upper and lower CUSUM accumulators), O(1) per-sensor ETS state for lock-free concurrent access, runtime-configurable lambda and threshold parameters via config signal, corrective fleet signals for deadlock and chaos prevention
USE_CASES: detecting mean shifts in temperature/pressure/throughput sensor streams, preventing fleet deadlock when all sensors converge to normal simultaneously (low entropy), escalating alerts when anomaly count exceeds safe entropy band (high entropy chaos), tuning CUSUM/EWMA parameters at runtime without restart, dashboard entropy gauge rendering
ARCHITECTURE: GenServer manages sensor registry and periodic entropy computation; ETS table holds per-sensor CUSUM/EWMA state (z_t upper/lower S_t accumulators) for lock-free concurrent reads; handle_signal/1 dispatches on signal topic: sensor readings update ETS and check CUSUM threshold, fleet heartbeats trigger Shannon entropy H = -sum(p(s)*log2(p(s))) over anomaly distribution, config signals update per-sensor params; implements Ichor.Mes.Subsystem behaviour with info/0, start/0, handle_signal/1, stop/0
DEPENDENCIES: Ichor.Signals, Ichor.Registry, AgentProcess
SIGNALS_EMITTED: [:mes, :anomaly, :detected], [:mes, :anomaly, :cleared], :entropy_alert, :entropy_dampening, :entropy_amplify
SIGNALS_SUBSCRIBED: [:mes, :sensor, :reading], [:mes, :anomaly, :configure], {:fleet_heartbeat, :snapshot}, {:agent_state_changed, :agent_id, :new_state}
