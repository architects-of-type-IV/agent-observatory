# Gate 1 Report — ARCHITECTS IV HYPERVISOR OBSERVATORY
Date: 2026-02-22

## Result: PASS (with minor issues noted)

All four checks pass. Two minor issues are flagged for cleanup before Stage 2; neither blocks progression.

---

## Check 1: ADR Coverage

All ten ADRs (ADR-013 through ADR-022) are covered by at least one FRD — either in the `source_adr` frontmatter or in the Related ADRs section.

| ADR | Covered By (frontmatter) | Also Referenced In (Related ADRs) | Status |
|-----|--------------------------|-----------------------------------|--------|
| ADR-013 | FRD-007 | FRD-007 Related ADRs | PASS |
| ADR-014 | FRD-006 | FRD-007, FRD-012 Related ADRs | PASS |
| ADR-015 | FRD-007 | FRD-009 Related ADRs | PASS |
| ADR-016 | FRD-008 | FRD-008 Related ADRs | PASS |
| ADR-017 | FRD-008 | FRD-006, FRD-008 Related ADRs | PASS |
| ADR-018 | FRD-009 | FRD-006, FRD-007, FRD-012 Related ADRs | PASS |
| ADR-019 | FRD-010 | FRD-010 Related ADRs | PASS |
| ADR-020 | FRD-010 | FRD-010 Related ADRs (broken link — see Issues) | PASS |
| ADR-021 | FRD-011 | FRD-009 Related ADRs | PASS |
| ADR-022 | FRD-012 | FRD-012 Related ADRs | PASS |

---

## Check 2: FR Consistency

| FRD | FR Count | FR Range | Sequential? | All have pos/neg? | source_adr consistent? | Status |
|-----|----------|----------|-------------|-------------------|------------------------|--------|
| FRD-006 | 9 | FR-6.1 – FR-6.9 | YES | YES | YES (ADR-014; also refs ADR-017, ADR-018 in body) | PASS |
| FRD-007 | 9 | FR-7.1 – FR-7.9 | YES | YES | YES (ADR-013, ADR-015; also refs ADR-014, ADR-018 in body) | PASS |
| FRD-008 | 13 | FR-8.1 – FR-8.13 | YES | YES | YES (ADR-016, ADR-017) | PASS |
| FRD-009 | 11 | FR-9.1 – FR-9.11 | YES | YES | YES (ADR-018; also refs ADR-015, ADR-021 in body — informational) | PASS |
| FRD-010 | 12 | FR-10.1 – FR-10.12 | YES | YES | YES (ADR-019, ADR-020; broken filename in link — see Issues) | PASS |
| FRD-011 | 11 | FR-11.1 – FR-11.11 | YES | YES | YES (ADR-021) | PASS |
| FRD-012 | 13 | FR-12.1 – FR-12.13 | YES | YES | YES (ADR-022; also refs ADR-014, ADR-018 in body — informational) | PASS |

Notes on source_adr vs. Related ADRs body references: several FRDs list their primary source ADR in frontmatter and then include additional contextually referenced ADRs in the Related ADRs body section. This is consistent and correct — the body references are informational cross-links, not contradictions. No mismatches found.

---

## Check 3: FR Quality Spot-Check

Sampled 2–3 FRs from each FRD against RFC 2119 language, specific module/field/endpoint naming, and meaningful positive/negative path distinction.

### FRD-006 — DecisionLog Schema

**FR-6.2 (Required Field Validation)** — Well-written. Uses MUST throughout. Names specific fields by dotted path (`meta.trace_id`, `identity.capability_version`), cites `validate_required/2` by name, and distinguishes HTTP 422 with the exact error message format `"missing required field: meta.trace_id"`. Positive and negative paths are concrete and non-trivial.

**FR-6.4 (action.status Enum Values)** — Well-written. Specifies the exact four atoms (`:success`, `:failure`, `:pending`, `:skipped`), the exact Ecto macro line, and the HTTP response body including the exact error message format `"invalid value for action.status: timeout"`. Negative path correctly exercises the inclusion validation path.

**FR-6.7 (entropy_score Gateway Overwrite)** — Well-written. Calls out specific module `Observatory.Mesh.EntropyComputer.compute/1`, the exact ordering constraint (after validation, before PubSub), and the nil-cognition guard. Positive and negative paths test different code branches.

No vague FRs found in FRD-006.

### FRD-007 — Gateway Schema Interceptor

**FR-7.4 (HTTP 422 Response)** — Well-written. Specifies the exact JSON response body shape with all four fields named, cites `Ecto.Changeset.traverse_errors/2`, and clarifies that `trace_id` is null when the message was rejected before a valid trace_id was confirmed. Negative path explicitly distinguishes 422 from 400 and explains the semantic reason.

**FR-7.6 (raw_payload_hash Security Policy)** — Well-written. Names the exact `:crypto.hash(:sha256, ...)` call, `Base.encode16/2` with case parameter, and the `"sha256:"` prefix format. Negative path describes the code review trigger (a `Logger.debug` call), which is specific and actionable.

**FR-7.8 (schema_violation Node State for Topology)** — Well-written. Names the `:schema_violation` atom, the hex color `#f97316`, the 30-second timeout, and the ghost node behavior for previously unseen agents. Both paths exercise meaningfully different branches.

No vague FRs found in FRD-007.

### FRD-008 — Causal DAG and Topology Engine

**FR-8.3 (Orphan Buffer and 30-Second Timeout)** — Well-written. Specifies the ETS key `{session_id, parent_step_id}`, the 30-second resolution window, the `:orphan` warning flag, and the exact behavior for both the timely-parent and timeout branches. The negative path tests the timeout branch specifically.

**FR-8.9 (topology_map.js Hook Structure)** — Well-written. Names the exact file path `assets/js/hooks/topology_map.js`, four required method names, the Canvas API call `this.el.querySelector('canvas').getContext('2d')`, and the LiveView event name `"topology_update"`. The negative path specifies `querySelector` returning null rather than a generic "error".

**FR-8.11 (Edge Click pushEvent Contract)** — Well-written. Specifies all three payload fields with their types for `edge_selected`, distinguishes node vs. edge vs. empty-canvas click behavior. Negative path tests a subtle no-op case (click on empty space).

No vague FRs found in FRD-008.

### FRD-009 — Entropy Loop Detection

**FR-9.3 (Uniqueness Ratio Computation)** — Well-written. Gives the exact formula `unique_count / window_size`, specifies exact tuple equality, float rounding to 4 decimal places, and provides a concrete worked example in the positive path with numeric values. Negative path tests the all-unique edge case.

**FR-9.4 (LOOP Threshold and Resulting Actions)** — Well-written. The three atomic actions are numbered explicitly, the config key `Application.get_env(:observatory, :entropy_loop_threshold, 0.25)` is named exactly, and the boundary condition (`< 0.25`, not `<= 0.25`) is tested in the negative path via score `0.25` landing in WARNING instead.

**FR-9.8 (Gateway Authoritative entropy_score)** — Well-written. Specifies the override order (after validation, after record_and_score), and the negative path handles the error tuple case precisely — retain agent-reported value and emit a log entry.

No vague FRs found in FRD-009.

### FRD-010 — Gateway Lifecycle

**FR-10.2 (Heartbeat Check Interval and Eviction Threshold)** — Well-written. Specifies both module attribute names `@eviction_threshold_seconds 90` and `@check_interval_ms 30_000`, calls `CapabilityMap.remove_agent(agent_id)` by name, and tests the eviction boundary at exactly 91 seconds.

**FR-10.9 (Exponential Backoff Retry Schedule)** — Well-written. Lists the complete retry schedule by attempt number, specifies the module attribute `@retry_schedule_seconds [30, 120, 600, 3600, 21600]`, names `DateTime.add/3` with `:second` unit, and tests the dead-entry path. The negative path addresses arithmetic drift risk specifically.

**FR-10.10 (HMAC-SHA256 Signature)** — Well-written. Cites `:crypto.mac(:hmac, :sha256, secret, payload_json)`, `Plug.Crypto.secure_compare/2` by name, specifies HTTP 401 with the `WebhookSignatureFailureEvent` side effect. Positive path verifies the signature match flow; negative path verifies the mismatch branch including the PubSub event.

No vague FRs found in FRD-010.

### FRD-011 — HITL Intervention API

**FR-11.2 (ETS Buffer Keyed by {session_id, agent_id})** — Well-written. Names the ETS table `:hitl_buffer`, specifies `ordered_set` semantics, the exact key tuple, the trace_id-matching rewrite lookup, and the HTTP 422 response body for not-found trace_id. The worked example in the positive path steps through T1/T2/T3 with the rewrite applied to T2.

**FR-11.6 (Operator Authentication via Header)** — Well-written. Names `conn.assigns[:operator_id]`, specifies `String.trim/1` application before the presence check, and defines Phase 2 isolation (only the plug changes, not the controller or HITLRelay). Negative path tests the whitespace-only value edge case.

**FR-11.9 (Automatic Pause on control.hitl_required)** — Well-written. Specifies the `operator_id: "system"` system actor string, the ordering constraint (pause before forwarding), and the downstream consequence if ordering is violated. Positive and negative paths test opposite conditions of the `hitl_required` flag.

No vague FRs found in FRD-011.

### FRD-012 — Hypervisor UI Architecture

**FR-12.1 (Six view_mode Atoms and Default View)** — Well-written. Lists all six atoms, specifies the mount ordering (assign fleet_command first, then read localStorage), and tests the no-localStorage case explicitly. Specific and unambiguous.

**FR-12.4 (localStorage Mismatch Recovery)** — Well-written. Lists specific legacy atoms by name (`:command`, `:pipeline`, `:agents`, etc.), specifies the `FunctionClauseError` prevention requirement, and defines both the hook-side guard and the LiveView-side catch-all as separate layers. Positive path tests the hook detection; negative path tests the LiveView fallback when a stale hook pushes an invalid atom.

**FR-12.11 (God Mode Kill-Switch Double-Confirm)** — Well-written. The two-step confirmation is precisely described with the socket assign enum `nil | :first | :second`, the reset-on-dismissal behavior, and a clear prohibition on single-press dispatch. Positive and negative paths test the happy path and the dismissal-at-step-1 branch.

No vague FRs found in FRD-012.

---

## Check 4: Cross-FRD FR Number Uniqueness

FR numbers use the pattern `FR-{frd_number}.{sequence}`, guaranteeing namespace isolation by construction:

- FRD-006 owns FR-6.x (FR-6.1 – FR-6.9)
- FRD-007 owns FR-7.x (FR-7.1 – FR-7.9)
- FRD-008 owns FR-8.x (FR-8.1 – FR-8.13)
- FRD-009 owns FR-9.x (FR-9.1 – FR-9.11)
- FRD-010 owns FR-10.x (FR-10.1 – FR-10.12)
- FRD-011 owns FR-11.x (FR-11.1 – FR-11.11)
- FRD-012 owns FR-12.x (FR-12.1 – FR-12.13)

No collisions exist. Each FR prefix corresponds to exactly one FRD.

**PASS**

---

## Issues Found

### Issue 1 (MINOR): Broken relative link in FRD-010 — ADR-020 filename mismatch

- **File**: `SPECS_DRAFT/requirements/frds/FRD-010-gateway-lifecycle.md`, line 152
- **Problem**: The Related ADRs section links to `../../decisions/ADR-020-webhook-reliability.md` but the actual filename on disk is `ADR-020-webhook-retry-dlq.md`. The link is broken; following it produces a 404.
- **Impact**: ADR coverage check passes because the ADR is referenced by ID (`ADR-020`) and the intent is clear. The broken filename does not invalidate the FRD's content. However, any automated link checker or cross-reference tool will report a broken reference.
- **Resolution**: Update line 152 of FRD-010 to read `../../decisions/ADR-020-webhook-retry-dlq.md`.

### Issue 2 (MINOR): FRD-009 source_adr frontmatter is narrower than body references

- **File**: `SPECS_DRAFT/requirements/frds/FRD-009-entropy-loop-detection.md`, frontmatter line 6
- **Problem**: The `source_adr` frontmatter lists only `[ADR-018]`, but the Related ADRs body section additionally references ADR-015 (Gateway Schema Interceptor, which calls `EntropyTracker.record_and_score/2`) and ADR-021 (HITL, which the Entropy Alert triggers). These references are accurate and correct — they reflect genuine dependencies. The frontmatter omission means automated tools that scan only frontmatter for ADR coverage would undercount FRD-009's reach.
- **Impact**: Does not affect correctness; ADR-015 and ADR-021 are already covered by FRD-007 and FRD-011 respectively. The omission is informational only.
- **Resolution** (optional): Expand `source_adr` to `[ADR-018, ADR-015, ADR-021]` for completeness, or leave as-is if `source_adr` is intentionally limited to the primary decision that motivated the FRD.

---

## Verdict

**PASS — proceed to Stage 2 (UC Writers)**

All four gate checks pass:
1. All 10 ADRs (ADR-013 through ADR-022) are covered by at least one FRD.
2. All 7 FRDs have sequential FR numbering with no gaps or duplicates, and every FR has both a positive path and a negative path.
3. FR quality is consistently high across all FRDs: RFC 2119 language is used throughout, module paths and field names are named specifically, and positive/negative paths test meaningfully distinct branches.
4. No cross-FRD FR number collisions exist.

The two minor issues above (broken ADR-020 link in FRD-010, narrow frontmatter in FRD-009) should be cleaned up but do not block Stage 2. UC Writers may proceed against all 7 FRDs as written.
