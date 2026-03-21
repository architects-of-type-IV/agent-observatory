# Sandboxed Teams: Design Specification

**Date:** 2026-03-21
**Status:** Design phase. Not yet implemented.

## Context

ICHOR IV / Observatory is an Elixir/Phoenix LiveView AI agent management dashboard. Today, agent teams (Claude Code, Codex, Aider) run on the local machine. This design introduces **sandboxed execution environments** that can be placed across multiple infrastructure providers -- local Firecracker microVMs, Kubernetes clusters, Fly.io Machines, and E2B sandboxes -- without changing the user experience.

**Problem:** Agent teams need isolation (security, dependencies, state), and the system should dynamically balance where teams run based on cluster health (disk, latency, locality, availability). Elixir's distributed BEAM makes local/remote seamless -- the sandbox layer should be equally transparent.

**Goal:** Spawn agent teams in composable, secure, lightweight sandboxes across any available infrastructure. The dashboard experience is unchanged -- users spawn teams and attach terminals as they do today.

## Design Principles

1. **Seamless** -- the user doesn't feel the difference from how things work today
2. **Pluggable** -- multiple providers behind a single behaviour
3. **Composable** -- fast boot, slim, layered, secure images
4. **Distributed** -- BEAM's native distribution makes local/remote equivalent
5. **Dynamic** -- scheduling based on disk, latency, locality, availability

## Architecture

### Provider Behaviour

```
Ichor.Sandbox.Provider  (behaviour)
  |-- Ichor.Sandbox.Provider.Firecracker   (direct REST, self-hosted, 125ms boot)
  |-- Ichor.Sandbox.Provider.Kubernetes    (agent-sandbox CRD, Kata/gVisor)
  |-- Ichor.Sandbox.Provider.Fly           (Machines API, managed Firecracker)
  |-- Ichor.Sandbox.Provider.E2B           (self-hosted or cloud, 80-200ms boot)
```

**Contract:**

```elixir
defmodule Ichor.Sandbox.Provider do
  @moduledoc "Behaviour for sandbox infrastructure providers."

  @type sandbox_id :: String.t()
  @type config :: %{
    image: String.t(),
    cpu: pos_integer(),
    memory_mb: pos_integer(),
    disk_mb: pos_integer(),
    env: map(),
    volumes: [{String.t(), String.t()}],
    network_policy: :full | :api_only | :none
  }

  @callback create(config()) :: {:ok, sandbox_id()} | {:error, term()}
  @callback exec(sandbox_id(), String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback attach(sandbox_id()) :: {:ok, port() | pid()} | {:error, term()}
  @callback status(sandbox_id()) :: :creating | :running | :stopped | :error
  @callback destroy(sandbox_id()) :: :ok | {:error, term()}
  @callback capacity() :: %{available: non_neg_integer(), total: non_neg_integer()}

  @callback snapshot(sandbox_id()) :: {:ok, String.t()} | {:error, term()}
  @callback restore(String.t()) :: {:ok, sandbox_id()} | {:error, term()}

  @optional_callbacks [snapshot: 1, restore: 1]
end
```

### Provider Implementations

#### Firecracker (direct)
- REST API client for local Firecracker via Unix socket
- Manages rootfs images, TAP networking, jailer config
- Fastest for local development (125ms boot)
- Elixir SDK: `seanmor5/firecracker`

#### Kubernetes (agent-sandbox)
- Posts SandboxClaim resources to K8s API
- Manages WarmPools for sub-second claims
- Uses `k8s` Hex package or raw HTTP
- Supports Kata Containers + gVisor RuntimeClasses

#### Fly.io (Machines)
- HTTP REST API to api.machines.dev
- Subsecond start from stopped state
- Managed Firecracker underneath
- BEAM-friendly ecosystem (FLAME library)

#### E2B
- REST API client (cloud or self-hosted)
- Purpose-built for AI agents
- 80-200ms boot, custom templates
- Self-hostable via Terraform on GCP/AWS

### Composable Image System

**Layer architecture:**
```
Layer 0: base       -- Alpine + agent CLIs (~40MB, no git)
Layer 1: runtime    -- elixir | node | php | python | rust (~30-200MB each)
Layer 2: lsp        -- elixir_ls | typescript-ls | intelephense (~10-50MB)
Layer 3: project    -- git worktree (volume mount, not baked in)
```

**Detection logic:**
- `mix.exs` present -> elixir runtime + elixir_ls
- `package.json` present -> node runtime + typescript-ls
- `composer.json` present -> php runtime + intelephense
- Multiple detected -> polyglot image with all required runtimes
- `.sandbox.yml` override -> explicit layer selection

Layers 0-2 are pre-built and cached. Layer 3 is a volume mount at spawn time.

### Sandbox Manager / Scheduler

`Ichor.Sandbox.Manager` is a GenServer that:

1. **Registers providers** at startup (configured in application env)
2. **Tracks capacity** per provider (periodic health checks)
3. **Routes requests** based on constraints:
   - Locality: prefer providers on the same network/region
   - Latency: measure round-trip to each provider
   - Availability: skip providers that are unhealthy
   - Disk: check available storage per provider
   - Cost: prefer cheaper providers when quality is equal
4. **Manages lifecycle** uniformly across providers
5. **Handles failover**: if a provider fails mid-sandbox, attempt migration or restart on another

**Scheduling algorithm:**
- Score each provider: `score = availability * (1/latency) * disk_available * locality_bonus`
- Pick highest score
- If provider create fails, try next highest

### Dashboard Integration

**Design principle:** The user spawns a team. The system decides where it runs. The terminal attaches seamlessly. No new UI concepts -- sandboxes are invisible infrastructure.

**What changes:**
- Team spawn may show a subtle indicator of where it's running (local/k8s/fly/e2b)
- Terminal attachment works identically (xterm.js -> WebSocket -> sandbox terminal)
- Status monitoring shows sandbox health alongside agent health

### Security Layer

**Per-sandbox controls:**
- **Network policy:** `full` (internet), `api_only` (only AI provider APIs), `none` (air-gapped)
- **Filesystem scope:** worktree mount is the only writable volume
- **Resource caps:** CPU cores, memory MB, disk MB, max runtime duration
- **Credential injection:** API keys passed as env vars, never baked into images
- **Audit logging:** all exec commands and file changes logged

### Git Strategy: No Git in Sandbox

**Key decision:** Git is NOT installed in sandboxes. All version control lives on the orchestrator side. This eliminates git binary (~30MB), .git directory (potentially huge), and SSH keys/credentials from the sandbox attack surface.

**Architecture:**
- `Ichor.Sandbox.GitProxy` -- GenServer on the orchestrator that handles git operations on behalf of sandboxes
- Sandboxes receive a flat file tree snapshot (no .git directory)
- File changes stream back to the orchestrator as diffs (inotify/fswatch or periodic sync)
- Orchestrator applies diffs and commits via git on the host side
- Git read operations (log, blame, diff, status) are exposed as remote API calls -- the agent asks the orchestrator, gets results back over the network

**Flow:**
1. Agent team requests a sandbox for project X
2. Orchestrator snapshots the file tree (tar/rsync) and sends to sandbox
3. Agent works on files normally (read, edit, create)
4. File changes stream back as diffs to the orchestrator
5. If agent needs git history/blame: remote call to GitProxy
6. On completion: orchestrator commits changes, cleans up sandbox

**Why this works:**
- Claude Code's Edit tool is already a diff protocol -- agents don't need `git commit`
- BEAM makes remote operations seamless -- GitProxy calls are just GenServer messages
- Smaller sandbox images, faster boot, stronger security
- Single source of truth for git state (orchestrator, not scattered across sandboxes)

## Files to Create

| File | Purpose |
|------|---------|
| `lib/ichor/sandbox/provider.ex` | Behaviour definition |
| `lib/ichor/sandbox/sandbox.ex` | Sandbox struct |
| `lib/ichor/sandbox/image.ex` | Image composition logic |
| `lib/ichor/sandbox/image/detector.ex` | Project type detection |
| `lib/ichor/sandbox/image/registry.ex` | Available image tracking |
| `lib/ichor/sandbox/manager.ex` | GenServer orchestrator |
| `lib/ichor/sandbox.ex` | Domain / public API |
| `lib/ichor/sandbox/providers/firecracker.ex` | Firecracker backend |
| `lib/ichor/sandbox/providers/kubernetes.ex` | K8s agent-sandbox backend |
| `lib/ichor/sandbox/providers/fly.ex` | Fly.io Machines backend |
| `lib/ichor/sandbox/providers/e2b.ex` | E2B backend |
| `lib/ichor/sandbox/git_proxy.ex` | Remote git operations for sandboxes |
| `sandbox-images/` | Dockerfiles/rootfs per layer |

## Files to Modify

| File | Change |
|------|--------|
| `lib/ichor_web/live/dashboard_live.ex` | Sandbox awareness in team spawn |
| `lib/ichor_web/live/dashboard_live.html.heex` | Sandbox status indicators |
| `assets/js/hooks/xterm_hook.js` | Remote sandbox terminal attachment |
| `lib/ichor_web/live/dashboard_tmux_handlers.ex` | Route tmux commands to sandbox |

## User Stories

```gherkin
Given a user is on the Observatory dashboard
When they spawn a new agent team for an Elixir project
Then the system detects the project type from mix.exs
And selects a sandbox image with Elixir + elixir_ls + git + Claude CLI
And creates a git worktree for the team's branch
And spawns the sandbox on the best available provider
And attaches the xterm.js terminal to the sandbox
And the user sees the agent working as if it were local

Given the Kubernetes cluster is at capacity
When a new team spawn request arrives
Then the manager falls back to Fly.io Machines
And the sandbox boots in <300ms
And the user experience is identical

Given an agent team finishes its work in a sandbox
When the team completes
Then changes are committed from the worktree
And the sandbox is destroyed
And resources are freed on the provider
```

## Acceptance Criteria

1. `mix compile --warnings-as-errors` passes with all new modules
2. Provider behaviour is implemented for all 4 backends
3. Sandbox Manager routes requests to providers based on capacity
4. Image detector correctly identifies project types
5. Git worktree creation and cleanup works end-to-end
6. xterm.js terminal attachment works for sandboxed agents
7. Security controls (network policy, resource caps) are enforced
8. Dashboard shows sandbox status without new UI paradigms
9. Existing team spawn flow works unchanged for local mode

## Key Technologies

| Component | Technology |
|-----------|-----------|
| microVM (local) | Firecracker (REST API, Elixir SDK: seanmor5/firecracker) |
| K8s sandboxing | kubernetes-sigs/agent-sandbox CRD + Kata Containers |
| Managed cloud | Fly.io Machines API |
| AI-native sandbox | E2B (self-hosted or cloud) |
| Image composition | OCI layers (Alpine base + runtime + LSP) |
| Project isolation | File tree sync + GitProxy (no git in sandbox) |
| Terminal attachment | xterm.js + WebSocket (existing) |
| Scheduling | GenServer with capacity-based scoring |

## Research References

- [Container & MicroVM Research](../research/containers.md)
- [Kubernetes Sandboxing Research](../research/kubernetes-sandboxing.md)
- [Architecture Decisions](../architecture/decisions.md) -- AD-1 through AD-8
