# host_registry

Tracks the BEAM nodes available to run work, with cluster-wide visibility.

Extracted from the ICHOR IV agent observatory, where each host ran tmux sessions
and agent processes and the scheduler needed to know which ones were alive. No
dependencies — just OTP's `:net_kernel` and `:pg`.

## Design

**Membership is observed, not declared.** Nodes appear as they join the cluster,
via `:net_kernel.monitor_nodes/2`. You can also register a host ahead of time,
so it is known before it comes online.

**A node that leaves is marked, not deleted.** It becomes `:disconnected` rather
than vanishing, because "was here and left" is worth knowing — an entry that
silently disappears looks identical to one that never existed.

| Status | Meaning |
|---|---|
| `:connected` | Reachable from here right now |
| `:registered` | Registered ahead of time, not yet reachable |
| `:disconnected` | Was connected, has since gone away |

**`available?/1` does not consult the registry.** It asks the VM directly, so a
stale entry can never make an unreachable node look usable. Use `list_hosts/0`
to see what is known, and `available?/1` to decide whether to send work — they
answer different questions and should not be conflated.

## Install

```elixir
def deps do
  [{:host_registry, path: "../host_registry"}]
end
```

```elixir
children = [HostRegistry]

config :host_registry,
  capabilities: [:tmux, :spawn],
  notifier: MyApp.HostNotifier
```

## Use

```elixir
HostRegistry.list_hosts()
#=> [%HostRegistry.Host{node: :"app@box-1", hostname: "box-1", status: :connected,
#=>                     capabilities: [:tmux, :spawn], connected_at: ~U[...], metadata: %{}}]

HostRegistry.list_connected()                              # connected only
HostRegistry.get_host(:"worker@box-2")                     # one host, or nil
HostRegistry.local_host()                                  # this node's entry

HostRegistry.register_host(:"worker@box-2", %{region: "eu"})
HostRegistry.remove_host(:"worker@box-2")

HostRegistry.available?(:"worker@box-2")                   # ask the VM, not the registry
HostRegistry.members()                                     # registries across the cluster
```

Metadata survives a reconnect: registering a host with `%{region: "eu"}` and
then watching it connect leaves the metadata intact, with only the liveness
fields changing.

## Cluster visibility

The registry joins a `:pg` process group, so registries on other nodes can find
each other through `members/0` without a central coordinator. The `:pg` scope is
started automatically if the host application has not already started it.

```elixir
config :host_registry,
  pg_scope: :my_app,
  pg_group: :hosts
```

## Notifications

`HostRegistry.Notifier` is how the registry tells a host application that the
fleet changed, without depending on the host's event system:

```elixir
defmodule MyApp.HostNotifier do
  @behaviour HostRegistry.Notifier

  @impl true
  def hosts_changed(hosts) do
    Phoenix.PubSub.broadcast(MyApp.PubSub, "fleet", {:hosts_changed, hosts})
  end
end
```

It receives the full host list as it now stands, so a consumer can render
without calling back in. It fires from inside the registry process, so a slow
implementation blocks node up/down handling — hand off if the work is not
trivial.

`HostRegistry.Notifier.ProcessMessage` ships as a ready-made adapter that sends
`{:host_registry, :hosts_changed, hosts}` to a configured pid or registered name.

## Tests

```
mix test
```

33 tests covering registration, removal, node up/down transitions, metadata
retention across a reconnect, and the notifier adapters. They drive the monitor
transitions by sending `:nodeup`/`:nodedown` directly, so no real cluster is
needed.

## Changes from the original

- Namespace `Ichor.Infrastructure.HostRegistry` → `HostRegistry`.
- `Ichor.Events.emit/1` replaced by the `HostRegistry.Notifier` behaviour,
  defaulting to a no-op.
- Host entries are a `HostRegistry.Host` struct rather than a bare map.
- The `:pg` scope and group, and the capability list, moved from module
  attributes to configuration. The scope is now started if absent, rather than
  assumed.

Fixed along the way:

- **A `nodedown` for an unknown node inserted a `nil` entry.** The handler used
  `Map.update(hosts, node, nil, fun)`, so a disconnect for a node the registry
  had never seen put `nil` into the map — and every later `list_hosts/0` returned
  it, crashing any consumer that touched the entry's fields. Unknown nodes are
  now ignored.
- **A reconnect wiped metadata.** `nodeup` built a fresh entry unconditionally,
  discarding whatever a prior `register_host/2` had recorded. It now updates the
  existing entry when there is one.
- `list_connected/0` and `members/0` are new.
