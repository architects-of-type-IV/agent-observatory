# Container & MicroVM Technology Research for AI Agent Sandboxing

**Date:** 2026-03-21
**Use case:** Running AI coding agents (Claude Code, Codex, Aider) in isolated sandboxed environments, controlled from an Elixir/BEAM application.

**Requirements:**
- Not Docker or Podman
- Linux-based
- Must run: CLI AI agents, git, npm/bun/node
- Smaller and faster the better
- Bonus: purpose-built for AI agents

---

## Quick-Reference Comparison

| Technology | Boot Time | Memory/Instance | HW VM Boundary | Full Userspace | API | Elixir SDK | Self-Host |
|---|---|---|---|---|---|---|---|
| **Firecracker** | 125ms | ~5MB + guest OS | Yes (KVM) | Yes | REST (Unix socket) | 2 libs (early) | Yes |
| **Cloud Hypervisor** | <100ms | Minimal + guest | Yes (KVM) | Yes | REST (HTTP) | DIY | Yes |
| **gVisor** | <100ms | ~20-30MB | No (userspace) | Mostly | OCI / Docker | DIY | Yes |
| **Kata Containers** | 150ms-3s | 50-100MB | Yes (KVM) | Yes | OCI / containerd | DIY | Yes |
| **LXC/Incus** | 1-3s | 50-100MB | No (shared kernel) | Yes | REST API | DIY | Yes |
| **systemd-nspawn** | <1s | Near zero | No (namespaces) | Yes | D-Bus / CLI | Painful | Yes |
| **Unikernels** | 10-50ms | Minimal | Depends | **NO** | VMM dependent | N/A | Yes |
| **Fly.io Machines** | 150-300ms | 256MB min | Yes (Firecracker) | Yes | REST API | DIY | No |
| **E2B** | 80-200ms | Configurable | Yes (Firecracker) | Yes | REST + SDKs | DIY | Yes |
| **Daytona** | Unknown | Unknown | Unknown | Yes | REST + SDKs | DIY | Yes |
| **Arrakis** | Unknown | Unknown | Yes (Cloud Hyp.) | Yes | REST + MCP | DIY | Yes |
| **krunai** | Sub-second | Low (libkrun) | Yes (KVM) | Yes | CLI only | Shell-out | Yes |

---

## Tier 1: Core Infrastructure Technologies

### Firecracker (AWS)

Open-source VMM that uses KVM to create minimal Linux microVMs. Powers AWS Lambda and Fargate.

- **Boot:** 125ms to first userspace process; up to 150 VMs/second creation rate
- **Overhead:** < 5 MiB per microVM (not counting guest OS + workload)
- **Rootfs:** requires a rootfs image; kernel ~10MB, Ubuntu rootfs ~200MB+, Alpine ~25MB
- **Userspace:** Yes -- guests run any Linux distro. Full bash, git, node, Claude CLI.
- **Security:** KVM hardware VM boundary + jailer (seccomp, cgroups, namespaces, privilege drop)
- **API:** RESTful HTTP API over Unix socket. Every lifecycle operation exposed.
- **Elixir:** `seanmor5/firecracker` (updated April 2025, low-level SDK) and `rozap/firex` (2021, less maintained). REST API is simple to wrap with Req/Tesla.
- **Status:** Actively maintained, Apache 2.0.
- **Requires:** KVM (`/dev/kvm`), x86_64 or aarch64 Linux host only -- no macOS. No nested KVM.
- **For Claude Code:** Claude CLI is Node.js, needs network for Anthropic API. Firecracker guests have full internet via TAP + routing. Bake Claude Code into rootfs image.

### Cloud Hypervisor (Intel/Linux Foundation)

Rust-based VMM for cloud workloads with minimal device emulation and direct kernel boot.

- **Boot:** < 100ms to userspace with direct kernel boot
- **Overhead:** Comparable to Firecracker. Rust implementation means low baseline.
- **Userspace:** Yes -- any Linux distribution.
- **Security:** KVM hardware VM boundary. Rust reduces memory-safety vuln surface.
- **API:** REST API (HTTP). Similar to Firecracker's API surface.
- **Elixir:** No existing SDK but REST API is trivial to wrap with Req/Mint.
- **Status:** Very active. v51.0 released February 2026. Intel, Microsoft, AMD backing.
- **More features than Firecracker:** QCOW2 v3, live migration, ACPI Generic Initiator. No jailer -- handle host security separately.

### gVisor (Google)

Application kernel written in Go that intercepts Linux syscalls in userspace.

- **Boot:** Milliseconds (process-like, no kernel boot)
- **Overhead:** ~20-30MB (Go runtime), plus per-syscall cost
- **Userspace:** Mostly yes. Node.js is regression-tested. Git works. Known gaps: io_uring disabled, no nested KVM.
- **Security:** Userspace sandbox -- NOT hardware VM. Reduces host kernel attack surface ~80%. Stronger than namespaces, weaker than KVM.
- **API:** OCI runtime -- integrate via containerd, Docker (`--runtime=runsc`), or Kubernetes.
- **Status:** Google-maintained. Powers Google Cloud Run and DigitalOcean App Platform.
- **Performance warning:** syscall-heavy workloads (npm install, git clone) are significantly slower (2-5x). For AI agent sandboxing with heavy I/O, this is a real concern.

### Kata Containers

OCI-compatible container runtime that boots a lightweight VM per container/pod.

- **Boot:** 150-300ms with Cloud Hypervisor or Firecracker VMMs. 1-3s with QEMU.
- **Overhead:** ~50-100MB per VM for guest kernel + kata-agent.
- **Userspace:** Yes -- full Linux VM per container.
- **Security:** Hardware VM boundary (KVM). Three-layer: host, guest VM, container.
- **API:** OCI runtime (containerd or CRI-O). Standard container APIs + Kubernetes CRI.
- **Status:** CNCF Incubating. Intel, Red Hat, IBM, Alibaba. Used in production at Baidu.
- **Best when you want:** "Docker but secure" with Kubernetes integration.

### LXC/LXD (Incus)

System container manager -- runs full Linux OS instances using namespaces/cgroups.

- **Boot:** 1-3 seconds for a full system container.
- **Overhead:** ~50-100MB (shared kernel).
- **Userspace:** Yes -- full Linux system with init, systemd, package managers.
- **Security:** Namespace + cgroup only (shared host kernel). Optional seccomp, AppArmor/SELinux.
- **API:** REST API (LXD/Incus).
- **Status:** Incus (community fork) active. Canonical LXD active.
- **Security concern:** shared kernel for untrusted agent code. Good for internal/trusted agents.

### systemd-nspawn

Lightweight container manager built into systemd. Heavy chroot with proper namespace isolation.

- **Boot:** Near-instant for process containers, 1-2s for full boot.
- **Overhead:** Essentially zero.
- **Userspace:** Yes -- full Linux system.
- **Security:** Namespace isolation only. Weakest isolation story.
- **API:** D-Bus / machinectl CLI. D-Bus is BEAM-unfriendly.
- **Good for:** Development/trusted environments only.

### Unikernels (MirageOS, NanoVMs/Nanos)

Single-application OS images compiled into a bootable kernel.

- **Boot:** 10-50ms
- **Overhead:** Tens of MB
- **Userspace:** **NO** -- one application, no bash, no package manager, no git, no npm.
- **Verdict:** Completely unsuitable. Claude Code depends on Node.js, npm, git, bash, writable filesystem.

---

## Tier 2: AI-Agent-Specific Platforms

### E2B (e2b.dev)

Purpose-built cloud sandbox infrastructure for AI agents. Firecracker microVMs underneath.

- **Boot:** 80-200ms (no cold starts)
- **Security:** Firecracker KVM hardware VM boundary.
- **Userspace:** Yes -- custom templates via Dockerfile-like spec. Git, node, npm, bun all installable.
- **API:** Python SDK, JavaScript/TypeScript SDK, REST API.
- **Elixir:** No SDK, but REST API wrappable.
- **Self-hosted:** Yes -- open-source infrastructure (GitHub: e2b-dev/infra, Go + Terraform). GCP fully supported, AWS in beta.
- **Status:** Series A ($21M). Active product development. Anthropic partnership.
- **Has MCP server integration.**

### Arrakis (abshkbh/arrakis)

Self-hosted AI agent sandboxing platform using Cloud Hypervisor microVMs.

- **Security:** Cloud Hypervisor KVM hardware VM boundary.
- **Userspace:** Yes -- Ubuntu guests. Custom rootfs via Dockerfile. Chrome, VNC pre-installed.
- **API:** REST API, Python SDK, MCP server (Claude Desktop integration), Go CLI.
- **Self-hosted:** Yes, fully. Prebuilt binaries.
- **Status:** Active (781 stars, 240 commits, March 2026 activity).
- **Has snapshot/restore** for agent backtracking (undo capability).

### Daytona

Open-source secure infrastructure for running AI-generated code. Programmatically controllable sandboxes.

- **Userspace:** Yes -- Docker/OCI images. Git operations, process execution, file I/O confirmed.
- **API:** Python, TypeScript, Go SDKs. REST API. CLI. Web Terminal, SSH, VNC.
- **Status:** Very active (68.9k GitHub stars, v0.154.0 March 2026). AGPL-3.0. Self-hostable.
- **Emphasizes:** "Git, LSP, and Execute API" -- VS Code Server / language server integration.

### krunai (slp/krunai)

CLI tool for running AI agents in microVM sandboxes using libkrun (lightweight KVM-based VMs).

- **Security:** KVM via libkrun.
- **Userspace:** Yes -- Debian base image, can install anything.
- **API:** CLI only. No REST API.
- **Works on both macOS and Linux** (libkrun uses Hypervisor.framework on macOS).
- **Status:** Active (v0.2.4 March 2026). Small project (34 stars).

### LuminaGuard (anchapin/luminaguard)

Local-first agentic AI runtime with JIT Firecracker microVMs + MCP integration.

- **Security:** Firecracker KVM + seccomp + firewall.
- **API:** Python and Rust APIs.
- **Status:** Active development (642 commits), no stable releases yet.

### BunkerVM

Self-hosted AI sandbox using Firecracker microVMs. Alpine Linux with Python 3.12.

- **Boot:** ~3 seconds (much slower than E2B).
- **Status:** Small project (57 commits).
- **Not recommended:** slow boot, narrow focus.

### Modal Sandboxes

Secure containers on Modal's cloud for executing untrusted AI-generated code.

- **Userspace:** Yes -- custom Docker images. GPU support.
- **API:** Python, JavaScript, Go SDKs. No direct REST API.
- **No self-host option.** Cloud-only.

### Fly.io Machines

Managed cloud: each "Machine" is a Firecracker microVM.

- **Boot:** ~300ms new, ~150ms from stopped state.
- **Security:** Firecracker KVM hardware VM boundary (managed).
- **Userspace:** Yes -- OCI images as rootfs.
- **API:** REST API (`api.machines.dev`). Official Go SDK.
- **Elixir:** No official SDK, but REST API is clean. Fly.io is BEAM-friendly (FLAME library).
- **Pricing:** Stopped machines ~$0.15/GB/month storage. Running billed by the second.
- **No self-host option.**

---

## The Agent Sandbox Taxonomy

From `kajogo777/the-agent-sandbox-taxonomy`:

**7 Defense Layers:**
1. **L1 Compute Isolation** -- hardware VM vs namespace vs process
2. **L2 Resource Limits** -- CPU/memory/disk/time caps
3. **L3 Filesystem Boundary** -- read/write/delete scope
4. **L4 Network Boundary** -- egress/ingress control
5. **L5 Credential Management** -- secrets isolation
6. **L6 Action Governance** -- semantic behavioral limits
7. **L7 Observability** -- audit logging

**Key insight:** No single technology covers all 7 layers well. Compose technologies: Firecracker for L1-L3, network policy for L4, secrets manager for L5, MCP tooling for L6.

---

## Strategic Analysis for BEAM/Elixir Control

**Best options for native BEAM control (ranked):**

1. **Firecracker (self-hosted)** -- REST API over Unix socket. Elixir SDK exists. Full control. Need KVM Linux host.
2. **Cloud Hypervisor (self-hosted)** -- REST HTTP API, trivial to wrap. More features than Firecracker.
3. **Fly.io Machines** -- HTTP REST API, BEAM-friendly. Managed cloud = no ops. Firecracker underneath.
4. **E2B (self-hosted)** -- REST API + open-source infra. Purpose-built for AI agents. Self-host on GCP/AWS.
5. **Arrakis** -- REST API, MCP server. Cloud Hypervisor backend. Snapshot/restore.

---

## Emerging Landscape (2025-2026)

- E2B raised $21M Series A
- Arrakis, ArcBox, krunai, LuminaGuard appeared on GitHub
- Daytona reached 68.9k stars
- Morph Labs emerged with "instant environment branching"
- Fly.io FLAME brought ephemeral BEAM-on-Firecracker to production
- `kubernetes-sigs/agent-sandbox` launched at KubeCon NA November 2025

**Convergence:** Firecracker (or Cloud Hypervisor) + OCI images + REST API is the standard stack. Differentiation is at orchestration: snapshot/restore, warm pools, network policy, MCP integration.
