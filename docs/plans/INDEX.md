# Plans & Audits Index

Generated: 2026-03-19

## Audit Reports

| File | Created | Description |
|------|---------|-------------|
| [2026-03-19-quality-audit.md](2026-03-19-quality-audit.md) | 2026-03-19 15:51 | Quality audit report covering lib/ichor/ and lib/ichor_web/ (read-only, no edits) |
| [audit-control.md](audit-control.md) | 2026-03-19 19:23 | Control domain deep audit -- function-by-function analysis of anti-patterns and Ash DSL misuse |
| [audit-projects.md](audit-projects.md) | 2026-03-19 19:27 | Projects domain deep audit -- 50+ modules, 100% pass-through wrappers and priority findings |
| [audit-observability-tools.md](audit-observability-tools.md) | 2026-03-19 19:27 | Observability + Tools domain audit -- code_interface misuse and Ash pattern findings |
| [audit-infrastructure.md](audit-infrastructure.md) | 2026-03-19 19:30 | Infrastructure & loose module audit -- all modules outside the 4 domain directories |

## Reference Documents

| File | Created | Description |
|------|---------|-------------|
| [xref-graph.txt](xref-graph.txt) | 2026-03-19 19:19 | Full xref dependency graph showing module-level import relationships |
| [ash-idioms-reference.md](ash-idioms-reference.md) | 2026-03-19 19:27 | Ash DSL patterns and anti-patterns reference -- condensed guide for auditing Elixir/Ash codebases |

## Architecture Plans

| File | Created | Description |
|------|---------|-------------|
| [2026-03-13-registry-redesign-design.md](2026-03-13-registry-redesign-design.md) | 2026-03-13 23:55 | Registry redesign design -- eliminate Gateway.AgentRegistry ETS duplication, single source of truth |
| [2026-03-13-registry-redesign.md](2026-03-13-registry-redesign.md) | 2026-03-13 23:55 | Registry redesign implementation plan -- Ichor.Registry as single source, Signals-based updates |
| [2026-03-15-genesis-nodes-design.md](2026-03-15-genesis-nodes-design.md) | 2026-03-15 01:43 | Genesis Nodes design -- MES teams produce briefs, Monad Method pipeline produces DAG-ready roadmaps |
| [2026-03-17-mes-unified-design.md](2026-03-17-mes-unified-design.md) | 2026-03-17 11:35 | MES unified factory view design -- pipeline position, stations, and artifact display (IMPLEMENTED) |
| [2026-03-18-umbrella-architecture.md](2026-03-18-umbrella-architecture.md) | 2026-03-18 19:51 | Full umbrella restructure architecture -- baseline for converting ichor into a Mix umbrella |
| [2026-03-18-module-classification.md](2026-03-18-module-classification.md) | 2026-03-18 19:51 | Module classification inventory -- pure_lib vs ash_domain vs runtime_shell for umbrella migration |
| [2026-03-19-de-umbrella-roadmap.md](2026-03-19-de-umbrella-roadmap.md) | 2026-03-19 00:32 | De-umbrella roadmap -- plan to collapse the umbrella scaffold back into a single ichor app |
| [2026-03-19-domain-consolidation.md](2026-03-19-domain-consolidation.md) | 2026-03-19 14:39 | Domain consolidation plan -- 10 Ash Domains collapsed into 4 (Control, Projects, Observability, Tools) |
| [2026-03-19-ash-ai-tool-scoping.md](2026-03-19-ash-ai-tool-scoping.md) | 2026-03-19 16:11 | AshAi tool scoping patterns -- research into Tool Profiles and MCP scoping via Ash Domain DSL |

## Genesis Feature Plans

| File | Created | Description |
|------|---------|-------------|
| [2026-03-17-genesis-mode-a-smoketest.md](2026-03-17-genesis-mode-a-smoketest.md) | 2026-03-17 11:35 | Genesis Mode A smoke test plan -- component verification (MCP tools, script gen, tmux + fleet) |
| [2026-03-17-genesis-tab-design.md](2026-03-17-genesis-tab-design.md) | 2026-03-17 11:35 | Genesis tab UI design -- master-detail layout with Decisions/Requirements/Checkpoints/Roadmap tabs |
| [2026-03-17-genesis-tab-plan.md](2026-03-17-genesis-tab-plan.md) | 2026-03-17 11:35 | Genesis tab implementation plan -- LiveView, Earmark markdown, Tailwind, Ash Genesis resources |

## Research

| File | Created | Description |
|------|---------|-------------|
| [2026-03-19-component-library-research.md](2026-03-19-component-library-research.md) | 2026-03-19 15:51 | Phoenix component library research -- SaladUI and alternatives for shadcn-style LiveView components |

## Process & Operations

| File | Created | Description |
|------|---------|-------------|
| [2026-03-19-merge-back-gates.md](2026-03-19-merge-back-gates.md) | 2026-03-19 00:32 | Merge-back gates -- checklist before merging any umbrella app back into apps/ichor |
| [2026-03-19-next-session-prompt.md](2026-03-19-next-session-prompt.md) | 2026-03-19 17:19 | Next session starter prompt -- handoff context after 10->4 domain refactor and file reorg task |
| [2026-03-19-next-priorities.md](2026-03-19-next-priorities.md) | 2026-03-19 20:30 | Codex-reviewed next session priorities -- RunProcess consolidation, spawn convergence, registry, wrappers |
| [VALIDATION.md](VALIDATION.md) | 2026-03-19 20:00 | Plan status validation -- tracks completion status of all plans |
