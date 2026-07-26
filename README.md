# tmux_channel

Deliver messages to processes running in tmux, and read their output back.

Extracted from the ICHOR IV agent observatory, where it is the transport for
talking to agents that each live in a tmux window. It has no dependencies —
just Elixir, OTP, and the `tmux` binary.

## Why it exists

Sending text to an interactive program in a tmux pane is more awkward than it
looks:

- **Writing to a temp file and having the target `cat` it** trips file-read
  permission prompts in the target program.
- **A single shared paste buffer** gets clobbered when two senders overlap.
- **`send-keys` immediately after `paste-buffer`** submits an empty line,
  because tmux pastes asynchronously.
- **Panes are spread across servers** — an explicit socket, a named server, the
  default server — and a reader that only checks one of them misses the rest.

`tmux_channel` handles all four: a uniquely named buffer per delivery, a settle
delay before Enter, and reads that fan out across every reachable server.

## Install

```elixir
def deps do
  [{:tmux_channel, path: "../tmux_channel"}]
end
```

## Use

```elixir
# Create a session
:ok = TmuxChannel.Launcher.create_session("team-a", "/srv/project", "builder", "cat")

# Send it a message
:ok = TmuxChannel.deliver("team-a", %{from: "scheduler", content: "status?"})

# Read the pane back
{:ok, output} = TmuxChannel.capture_pane("team-a")
{:ok, raw}    = TmuxChannel.capture_pane("team-a", ansi: true)

# Look around
TmuxChannel.list_sessions()              #=> ["team-a"]
TmuxChannel.list_windows("team-a")       #=> [%{name: "builder", target: "team-a:builder"}]
TmuxChannel.list_panes()                 #=> [%{pane_id: "%0", session: "team-a", ...}]
TmuxChannel.available?("team-a")         #=> true
```

Addresses are either session names or pane ids (`%3`); `available?/1` tells them
apart by the leading `%`.

## Modules

| Module | Role |
|---|---|
| `TmuxChannel` | Delivery, pane capture, and listings |
| `TmuxChannel.Channel` | Behaviour for delivery adapters — implement it for non-tmux transports |
| `TmuxChannel.Launcher` | Session and window lifecycle, targeting one server deterministically |
| `TmuxChannel.Script` | Writes the prompt file and launch script for an agent |
| `TmuxChannel.Command` | `System.cmd/3` wrapper with multi-server fallback |
| `TmuxChannel.ServerSelector` | Resolves and caches which servers to try |
| `TmuxChannel.Parser` | Parses tmux's tab-delimited `-F` output |
| `TmuxChannel.Config` | All runtime configuration, with defaults |

### Read fan-out vs. deterministic writes

`TmuxChannel` reads across every server in priority order and takes the first
success, so it finds panes wherever they are. `TmuxChannel.Launcher` targets a
single server — the socket if it exists, otherwise the named server — because
"whichever server answered first" is fine for a query and wrong for
`new-session`.

## Configuration

Everything has a working default; none of this is required.

```elixir
config :tmux_channel,
  socket_path: "~/.tmux_channel/tmux.sock",  # tried first, when the file exists
  server_name: "tmux_channel",               # tmux -L <name>
  buffer_prefix: "tmux-channel",             # prefix for per-delivery buffer names
  server_cache_ttl_ms: 5_000,                # how long a process caches server resolution
  paste_settle_ms: 150,                      # delay between paste-buffer and Enter
  script_command: "env -u CLAUDECODE claude",
  model_flag: "--model",
  permission_profiles: %{
    "builder" => ["--dangerously-skip-permissions"],
    "scout" => ["--allowedTools", "Read", "Glob", "Grep"]
  }
```

`permission_profiles` maps a capability name to the extra CLI arguments
`TmuxChannel.Script` appends. An unknown capability adds nothing, so the default
is always the least privileged.

If `paste_settle_ms` is too low you will see empty lines submitted instead of
your message; raise it on a loaded host.

## Tests

```
mix test
```

Tests that need a real tmux server are tagged `:tmux` and create their own
throwaway server, so they never touch your sessions. They are skipped
automatically when `tmux` is not on `PATH`.

## Changes from the original

- Namespace `Ichor.Infrastructure.Tmux.*` → `TmuxChannel.*`; the `Channel`
  behaviour moved in alongside it.
- Hardcoded `~/.ichor/tmux/obs.sock` and `-L obs` are now configuration, with
  neutral defaults. To keep the original behaviour, set `socket_path:
  "~/.ichor/tmux/obs.sock"` and `server_name: "obs"`.
- The Jason fallback for a payload with no `:content` is now `inspect/1`, which
  removes the last dependency.
- Pane-line parsing moved into `TmuxChannel.Parser` so it is testable without a
  running tmux.
- Script arguments are shell-quoted, so a path containing a quote can no longer
  break out of the generated script.
- `Command.run/1` now returns `{:error, :tmux_not_found}` instead of raising
  when there is no `tmux` on `PATH`.
- `Launcher.send_exit/2` takes the text to send, defaulting to `/exit`.
