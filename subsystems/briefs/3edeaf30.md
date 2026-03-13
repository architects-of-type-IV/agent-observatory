TITLE: Temporal Signal Correlator
DESCRIPTION: Correlates time-series signals from heterogeneous agent sources using sliding-window cross-correlation and adaptive thresholding. Identifies causal relationships, phase drift, and anomalous signal bursts across fleet agent channels in real time.
SUBSYSTEM: Ichor.Subsystems.TemporalSignalCorrelator
SIGNAL_INTERFACE: Subscribes to :agent_signal, :fleet_heartbeat, :entropy_sample; emits :correlation_update, :anomaly_detected, :phase_drift_alert
TOPIC: subsystem:temporal_signal_correlator
VERSION: 0.1.0
FEATURES: sliding-window cross-correlation, adaptive anomaly threshold, per-channel phase drift detection, multi-agent signal fan-in, ETS-backed ring buffer, self-healing on stale channels
ARCHITECTURE: GenServer with ETS ring-buffer per channel (configurable window 1s–60s). On each :agent_signal, updates the relevant channel buffer, runs O(n) cross-correlation against all active channels, computes z-score anomaly score against rolling baseline, and broadcasts results via Phoenix.PubSub. Adaptive thresholds recomputed every 5s using EWMA over recent signal variance. Channels inactive >30s are tombstoned and their buffers pruned.
DEPENDENCIES: Ichor.Registry, Ichor.Gateway.AgentProcess, Phoenix.PubSub
SIGNALS_EMITTED: :correlation_update, :anomaly_detected, :phase_drift_alert, :channel_tombstoned
SIGNALS_SUBSCRIBED: :agent_signal, :fleet_heartbeat, :entropy_sample

---

## Coordinator Notes

Run ID: 3edeaf30
Synthesized from domain knowledge (fallback path — researcher agents dispatched but check_inbox not available in this environment).

### Researcher-1 Assignment
signal correlation — sliding-window cross-correlation between agent signal streams

### Researcher-2 Assignment
anomaly detection — EWMA adaptive thresholding + z-score burst detection

### Key Algorithm: Sliding-Window Cross-Correlation
For N channels with window W:
1. Maintain ETS ring buffer per channel (size W)
2. On new sample: push to buffer, compute cross-correlation matrix (NxN)
3. Anomaly score = |z| > threshold (adaptive EWMA baseline)
4. Phase drift = argmax of cross-correlation lag vector

### Self-Healing
- Channels inactive > 30s → tombstoned, buffer freed
- On channel resurrection → baseline reset, warmup period of 5s
- Supervisor restarts GenServer on crash; ETS owned by supervisor (persistent across restarts)
