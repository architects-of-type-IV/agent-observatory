# The Signal Transport Stack

| Layer | Module | Role |
|-------|--------|------|
| Facade | `Ichor.Signals` | Ash Domain + runtime facade, delegates to impl() |
| Behaviour | `Ichor.Signals.Behaviour` | Contract: emit/subscribe/unsubscribe |
| Runtime | `Ichor.Signals.Runtime` | PubSub broadcast, telemetry, topic routing |
| Test impl | `Ichor.Signals.Noop` | Silent impl for tests |
| Catalog | `Ichor.Signals.Catalog` | 143 signal definitions (name, category, keys, doc) |
| Topics | `Ichor.Signals.Topics` | Topic string builders |
| Message | `Ichor.Signals.Message` | Envelope struct |
