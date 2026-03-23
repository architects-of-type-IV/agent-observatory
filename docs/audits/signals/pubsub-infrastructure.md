# PubSub Infrastructure

**One system**: `Ichor.PubSub` (Phoenix.PubSub, started in application.ex)

Direct PubSub callers that bypass `Signals.emit/subscribe`:
- `buffer.ex` -- broadcasts on `"signals:feed"` (UI feed)
- `dashboard_live.ex` -- subscribes to `"signals:feed"`
- `dashboard_messaging_handlers.ex` -- subscribes to `"agent:#{session_id}"`
- `plugin_scaffold.ex` -- subscribes to `"plugin:#{app_name}"`

All signal transport goes through `Signals.Runtime` which wraps PubSub.
