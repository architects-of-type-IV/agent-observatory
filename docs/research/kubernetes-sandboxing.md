# Kubernetes-Based Self-Hosted AI Agent Sandboxing Research

**Date:** 2026-03-21
**Use case:** Elixir/Phoenix application spawning isolated environments for CLI AI agents (Claude Code, Codex, Aider) on self-hosted Kubernetes.

---

## Isolation Tiers

| Tier | Mechanism | Kernel shared? | Boot time | Cost |
|------|-----------|----------------|-----------|------|
| Container (runc) | cgroups + namespaces | Yes | <100ms | Lowest |
| Syscall intercept (gVisor) | User-space kernel | No (intercepted) | ~50-100ms | Medium CPU overhead |
| microVM / full VM | Hypervisor (KVM) | No (own kernel) | 125ms-5s+ | Highest, hw-isolated |

---

## Quick-Reference Comparison

| Technology | Isolation | Boot (warm) | Boot (cold) | Userspace | API | Complexity | Scale |
|---|---|---|---|---|---|---|---|
| **agent-sandbox + Kata** | microVM (RuntimeClass) | <1s (warm pool) | 150-300ms | Yes | K8s REST | Medium | 1000s |
| **agent-sandbox + gVisor** | Syscall intercept | <1s (warm pool) | 50-100ms | Mostly | K8s REST | Low-Med | 1000s |
| **Kata Containers alone** | microVM | 150-300ms | 150-300ms | Yes | K8s REST | Medium | 100s-1000s |
| **gVisor alone** | Syscall intercept | 50-100ms | 50-100ms | Mostly | K8s REST | Low-Med | 100s-1000s |
| **Edera** | Type-1 hypervisor | ~650ms | ~650ms | Yes | K8s REST | High | 100s |
| **KubeVirt** | Full KVM VM | 30-90s | 30-90s | Yes | K8s REST | High | 10s-100s |
| **Virtink** | Cloud Hypervisor VM | 10-30s | 10-30s | Yes | K8s REST | Med-High | 10s-100s |
| **Nomad + Firecracker** | microVM | 1-5s | 1-5s | Yes | HTTP REST | Low-Med | 1000s |
| **K3s** | Cluster layer | N/A | N/A | N/A | K8s REST | Low | 10-1000s |
| **MicroK8s** | Cluster layer | N/A | N/A | N/A | K8s REST | Low | 10-100s |
| **Talos Linux** | Cluster OS | N/A | N/A | N/A | gRPC/K8s | High init | 10-1000s |

---

## The Key Discovery: kubernetes-sigs/agent-sandbox

An **official Kubernetes SIG Apps project** (launched KubeCon Atlanta, November 2025) providing a `Sandbox` CRD and controller designed specifically for AI agent execution.

### What it provides
- **Sandbox CRD** -- declare a sandbox, controller provisions it
- **SandboxClaim** -- request a sandbox (optionally from a warm pool)
- **WarmPool CRD** -- pre-warmed sandboxes for sub-second claims (90% faster than cold starts)
- **Pluggable backends** -- gVisor (default), Kata Containers (microVM)
- **Sandbox Router** -- HTTP proxy into the sandbox for command execution

### Elixir integration path
```
Elixir app → POST SandboxClaim (K8s REST API) → Controller provisions sandbox
           → exec commands via API or Sandbox Router
           → DELETE when done
```

Use the `k8s` Hex package or raw HTTP to kube-apiserver.

### Status
- Under `kubernetes-sigs` (official Kubernetes org)
- v0.1.0 (late 2025), backed by Google
- Joint integration with Kata Containers documented
- Expected to mature quickly given corporate backing

---

## Isolation Runtimes (RuntimeClass-based)

### Kata Containers

OCI-compliant runtime that boots a lightweight VM per pod using QEMU, Cloud Hypervisor, or Firecracker.

- **Boot:** 150-300ms (Cloud Hypervisor/Firecracker), 1-3s (QEMU)
- **Isolation:** Hardware VM (KVM). Each pod gets its own kernel. Container escape requires escaping guest kernel AND hypervisor.
- **Userspace:** Full Linux. Any tools installable.
- **K8s integration:** `RuntimeClass` resource. Pods look identical to normal pods.
- **Self-host:** Install containerd + Kata on nodes, create RuntimeClass. Needs KVM. Works on K3s, MicroK8s, vanilla K8s, Talos.
- **Status:** CNCF Incubating. Intel, Red Hat, IBM, Alibaba. Major clouds (AKS, ACK) use it.
- **Scale:** 50-200 concurrent sandboxes per node. 100s-1000s at cluster scale.

**Primary recommendation** for AI agent sandboxing on K8s.

### gVisor (runsc)

User-space kernel in Go that intercepts syscalls. No VM, no separate kernel boot.

- **Boot:** 50-100ms. Very fast.
- **Isolation:** Syscall interception. ~80% kernel attack surface reduction. NOT hardware VM.
- **Userspace:** Mostly yes. Node.js regression-tested. Git works.
- **Performance warning:** npm install and git clone are I/O-heavy. gVisor can be 2-5x slower for these. A 30-second npm install becomes 60-150 seconds.
- **Self-host:** Install `runsc` on nodes. No KVM required. Works on any Linux node.
- **Status:** Google-maintained. Powers GKE Sandbox.
- **Scale:** 200-500+ per node (no per-VM overhead).

Good for high-density when KVM isn't available. Significant I/O performance penalty.

### Edera

Container-native Type-1 hypervisor (Xen in Rust). Each container gets its own kernel.

- **Boot:** ~650ms additional over runc.
- **Isolation:** Type-1 hypervisor. Own kernel per container.
- **Performance:** 10.2% CPU overhead vs runc, 8.3% memory overhead. Outperforms gVisor.
- **Status:** Active startup ($20M raised 2024). Younger than Kata/gVisor.
- **Requires Xen** -- more complex to operate.

Worth watching. Currently less mature.

---

## VM-as-Pod (Full VM in K8s)

### KubeVirt

Runs full KVM VMs as Kubernetes resources (CRD: `VirtualMachineInstance`).

- **Boot:** 30-90 seconds. Full OS boot.
- **Isolation:** Full hardware VM. Strongest possible.
- **Status:** CNCF, applying for Graduation. 41 production adopters.
- **Complexity:** High. Persistent storage, networking, live migration all need expertise.
- **Verdict:** **Wrong tool** for ephemeral sandboxes. 30-90s boot is a dealbreaker. Designed for long-lived VM workloads.

### Virtink

Lightweight K8s add-on for Cloud Hypervisor VMs.

- **Boot:** 10-30s (still guest OS boot constrained).
- **Overhead:** ~30MB VM overhead (vs KubeVirt's much more).
- **Status:** Less active, pre-1.0. API may change.
- **Verdict:** Architecturally interesting but immature. KubeVirt is safer in the full-VM category. Neither is right for ephemeral sandboxes.

---

## Dedicated Sandbox/Workspace Operators

### DevWorkspace Operator (devfile)

K8s operator for managing cloud development environments. Backs Eclipse Che.

- **Isolation:** Standard pod/namespace (runc). No extra runtime isolation.
- **Focus:** Human developer workspaces with IDE integration, OAuth, Devfile spec.
- **Verdict:** Wrong fit. Designed for humans in IDEs, not programmatic AI agent sandboxes.

---

## Kubernetes Distributions (cluster layer)

### K3s

CNCF-certified lightweight K8s distribution. Single ~100MB binary.

- **Setup:** Extremely easy (`curl | sh`). Single-binary, embedded etcd or SQLite.
- **RuntimeClasses:** All work (Kata, gVisor).
- **Scale:** Best for clusters under ~50 nodes.
- **Status:** CNCF-graduated. Rancher/SUSE maintained.
- **Verdict:** Excellent choice for self-hosted sandbox cluster. Minimal ops overhead.

### MicroK8s

Canonical's lightweight K8s via snap package. Built-in addon system.

- **Setup:** Single command on Ubuntu/snap systems.
- **HA:** Multi-node with Dqlite.
- **Verdict:** Alternative to K3s. Better if already on Ubuntu. K3s has broader support.

### Talos Linux

Immutable, API-managed Linux OS purpose-built for Kubernetes. No SSH, no shell.

- **Security:** Dramatically reduced attack surface. No configuration drift. Perfect for security-sensitive workloads.
- **Pairing:** Immutable host OS + Kata/gVisor = container escape hits minimal, shell-less host.
- **Complexity:** High learning curve initially (no SSH). Low operational drift once running.
- **Status:** Sidero Labs maintained. Growing community.
- **Verdict:** Excellent node OS for production sandbox clusters. High initial complexity pays off for security.

---

## Infrastructure & Multi-tenancy

### Crossplane

CNCF K8s extension for provisioning infrastructure via CRDs. "Terraform as a K8s operator."

- **Not a sandbox solution.** Provisions infrastructure (VMs, databases, clusters).
- **Relevant if:** You need to auto-scale cluster capacity as agent demand grows.
- **Complementary** to the sandbox layer, not a replacement.

### vCluster

Virtual Kubernetes clusters inside a host cluster namespace.

- **Isolation:** Control plane isolation (separate API server, RBAC, CRDs). Workload isolation unchanged.
- **Granularity:** Per-team/tenant, NOT per-session.
- **Verdict:** Wrong granularity for per-session sandboxing. Designed for "give customer X their own cluster."

---

## Non-K8s: HashiCorp Nomad

Workload orchestrator supporting containers, executables, QEMU VMs, and more.

- **Isolation drivers:** exec (cgroups/namespaces), QEMU (full VM), Docker, Firecracker (community plugin).
- **API:** First-class HTTP REST API. Clean, well-documented. Easier than K8s API from an app.
- **Elixir:** `nomad_api` Hex package or raw HTTP.
- **Scale:** Documented at 10,000+ nodes.
- **License warning:** BSL (Business Source License) since v1.6+. IBM acquired HashiCorp 2024. Restricts competitive hosted offerings but allows self-hosted deployment.
- **Verdict:** Technically excellent. HTTP API is Elixir-friendly. BSL license is the risk.

---

## Firecracker on K8s

### Kata Containers + Firecracker VMM

The production-recommended path for Firecracker on Kubernetes.

- **Boot:** 125-200ms.
- **Self-host:** Bare metal or nested virt with `/dev/kvm`.
- **Verdict:** Cleanest path for Firecracker isolation on K8s.

### Weave Ignite / Flintlock

- **Ignite:** Archived/abandoned.
- **Flintlock:** Provisions K8s *nodes* as Firecracker microVMs (Cluster API provider). Not for per-session sandboxing.

---

## Recommended Stack

| Layer | Technology | Why |
|-------|-----------|-----|
| Cluster OS | Talos Linux | Immutable, minimal attack surface |
| Distribution | K3s | Lightest ops, single binary, full K8s API |
| Isolation | Kata + Cloud Hypervisor | microVM, 150-300ms, full Linux |
| Sandbox CRD | agent-sandbox | Purpose-built for AI agents, warm pools |
| Elixir control | `k8s` Hex or raw HTTP | Standard K8s REST API |

---

## Sources

- [kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
- [Agent Sandbox project site](https://agent-sandbox.sigs.k8s.io/)
- [Open-Source Agent Sandbox on K8s - InfoQ](https://www.infoq.com/news/2025/12/agent-sandbox-kubernetes/)
- [Google: Unleashing AI agents on K8s](https://opensource.googleblog.com/2025/11/unleashing-autonomous-ai-agents-why-kubernetes-needs-a-new-standard-for-agent-execution.html)
- [Kata Containers + Agent Sandbox Integration](https://katacontainers.io/blog/kata-containers-agent-sandbox-integration/)
- [Kata Containers official site](https://katacontainers.io/)
- [gVisor documentation](https://gvisor.dev/docs/)
- [Agent Sandbox on gVisor](https://agent-sandbox.sigs.k8s.io/docs/guides/gvisor/)
- [KubeVirt architecture](https://kubevirt.io/user-guide/architecture/)
- [Virtink GitHub](https://github.com/smartxworks/virtink)
- [vCluster documentation](https://www.vcluster.com/docs/vcluster/introduction/what-are-virtual-clusters)
- [Crossplane official site](https://www.crossplane.io/)
- [HashiCorp Nomad documentation](https://developer.hashicorp.com/nomad/docs/what-is-nomad)
- [K3s documentation](https://docs.k3s.io/)
- [MicroK8s - Canonical](https://canonical.com/microk8s)
- [Talos Linux](https://www.talos.dev/)
- [Edera for Kubernetes](https://edera.dev/protect-kubernetes)
- [How to sandbox AI agents 2026 - Northflank](https://northflank.com/blog/how-to-sandbox-ai-agents)
- [DevWorkspace Operator GitHub](https://github.com/devfile/devworkspace-operator)
- [Nomad Firecracker task driver](https://github.com/cneira/firecracker-task-driver)
- [Flintlock GitHub](https://github.com/liquidmetal-dev/flintlock)
