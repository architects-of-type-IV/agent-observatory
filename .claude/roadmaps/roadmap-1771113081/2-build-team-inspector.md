# Phase 2: Build Team Inspector

## Goals
- Add :teams view mode to Observatory dashboard
- Build bottom drawer inspector with team stack management
- Build tmux-like maximized tiled view with live event streaming
- Build multi-target message composer (7 granularities)

## Linked Decisions
- View mode: :teams (10th view mode, within existing LiveView)
- Live output: event stream via PubSub events:stream (not raw terminal)
- Empty inspector: collapsed bar with hint text
- Bottom drawer: new CSS pattern (no existing drawer in codebase)

## Success Criteria
- `mix compile --warnings-as-errors` passes
- All modules under 300 lines
- Teams tab visible in header, keyboard shortcut `9` works
- Bottom inspector slides up when team inspected
- Maximize mode shows tmux-like tiled layout
- Message composer targets all 7 granularities
- Messages deliver via Mailbox + CommandQueue
