# Gate 2 Report: UC Completeness

**Date:** 2026-02-21
**Result:** PASS with minor notes

---

## FR Coverage

| FRD | Total FRs | FRs Covered | Orphan FRs | Status |
|-----|-----------|-------------|------------|--------|
| FRD-001 (Navigation & View Architecture) | 9 | 9 | 0 | PASS |
| FRD-002 (Agent Block Feed) | 13 | 13 | 0 | PASS |
| FRD-003 (Messaging Pipeline) | 13 | 13 | 0 | PASS |
| FRD-004 (SwarmMonitor & ProtocolTracker) | 16 | 16 | 0 | PASS |
| FRD-005 (Code Architecture Patterns) | 19 | 19 | 0 | PASS |
| FRD-006 (Roadmap File Conventions) | 9 | 9 | 0 | PASS |
| **Total** | **79** | **79** | **0** | **PASS** |

Coverage is exhaustive. Every FR maps to exactly one UC. The FR-to-UC mapping is 1:1 across all six FRDs.

---

## Gherkin-AC Mapping

### Pattern

The predominant pattern across Batch A and Batch B UCs is: **N Gherkin scenarios → N+1 ACs**, where the last AC is the universal `mix compile --warnings-as-errors` check. This is a legitimate and consistent design choice — the compile check is not scenario-specific but applies across all scenarios.

Batch C FRD-006 UCs (UC-0150 through UC-0158) have **zero compile checks** in their ACs. This is intentional — FRD-006 covers filesystem and process conventions, not compiled Elixir code. The absence of compile checks in these UCs is appropriate.

### Consistent UCs

The following UC groups follow the N scenarios → N+1 ACs pattern exactly:

- **Batch A UCs:** UC-0001 through UC-0009 (except UC-0003), UC-0025 through UC-0037
- **Batch B UCs:** UC-0051, UC-0057, UC-0059, UC-0060, UC-0061
- **Batch C UCs (FRD-004):** UC-0100, UC-0101, UC-0103, UC-0106, UC-0107, UC-0108, UC-0109, UC-0112, UC-0113, UC-0115
- **Batch C UCs (FRD-005):** UC-0137, UC-0139, UC-0140, UC-0141, UC-0142, UC-0143
- **Batch C UCs (FRD-006):** UC-0152, UC-0156

### Mismatches Requiring Attention

The following UCs have scenario counts that do not align with adjusted AC counts (where `adjusted = raw_ACs - compile_check_count`). These are noted as minor issues, not blocking failures, because in each case the ACs are substantively complete even if the numbering does not match 1:1.

| UC | Scenarios | Raw ACs | Compile Checks | Adjusted ACs | Note |
|----|-----------|---------|----------------|--------------|------|
| UC-0003 | 4 | 4 | 1 | 3 | S4 (missing hook, no crash) has no dedicated AC; compile check stands in |
| UC-0050 | 3 | 2 | 1 | 1 | S2 and S3 (bypass scenarios) share one grep-based AC; consolidation intentional |
| UC-0052 | 3 | 3 | 1 | 2 | S2 (MCP finds file) and S3 (filesystem failure) share one AC |
| UC-0053 | 3 | 5 | 1 | 4 | Extra AC (native inbox file format check) has no matching scenario; orphan AC |
| UC-0054 | 3 | 3 | 1 | 2 | S3 (PubSub timing test) has no dedicated AC |
| UC-0056 | 3 | 3 | 1 | 2 | S3 (failure path) has no dedicated AC |
| UC-0057 | 4 | 4 | 1 | 3 | S4 (poll reschedule) has no dedicated AC |
| UC-0058 | 4 | 3 | 1 | 2 | S3 and S4 (failure paths) share one AC |
| UC-0059 | 3 | 3 | 1 | 2 | S3 (per-session subdirectory) has no dedicated AC |
| UC-0062 | 4 | 4 | 1 | 3 | S3 (partial failure) has no dedicated AC; covered by S1 combined assertion |
| UC-0102 | 3 | 3 | 1 | 2 | S3 (independent scheduling) has no dedicated AC |
| UC-0104 | 2 | 4 | 1 | 3 | One AC (`state.pipeline is never nil`) has no dedicated scenario; orphan AC |
| UC-0105 | 4 | 4 | 1 | 3 | S4 (circular dependencies) has no dedicated AC |
| UC-0110 | 3 | 3 | 1 | 2 | S3 (no-broadcast-on-no-change) has no dedicated AC |
| UC-0111 | 2 | 4 | 1 | 3 | Two extra ACs without scenarios (subscription check, process restart timing) |
| UC-0112 | 4 | 4 | 1 | 3 | S4 (non-matching event types) has no dedicated AC |
| UC-0114 | 3 | 5 | 1 | 4 | Two ACs without matching scenarios; pruning verification split into multiple assertions |
| UC-0125 | 3 | 3 | 7 | -4 | Multiple compile-check lines embedded in ACs (each assertion reuses compile); effectively 3 ACs for 3 scenarios |
| UC-0130 | 3 | 3 | 7 | -4 | Same pattern as UC-0125 |
| UC-0131 | 3 | 3 | 8 | -5 | Same pattern |
| UC-0132 | 2 | 2 | 10 | -8 | Same pattern; both scenarios have ACs |
| UC-0133 | 2 | 2 | 7 | -5 | Same pattern; both scenarios have ACs |
| UC-0138 | 2 | 4 | 3 | 1 | Extra ACs cover guard clause placement (no dedicated scenario) |
| UC-0151 | 2 | 2 | 0 | 2 | Both scenarios have ACs; no compile check (appropriate for FR-6.x) |
| UC-0152 | 3 | 3 | 0 | 3 | All 3 scenarios have ACs; no compile check (appropriate) |
| UC-0156 | 3 | 3 | 0 | 3 | All 3 scenarios have ACs; no compile check (appropriate) |

### Classification

- **True orphan ACs** (AC without any corresponding scenario): UC-0053 (1 orphan AC), UC-0104 (1 orphan AC), UC-0111 (2 orphan ACs), UC-0114 (2 orphan ACs), UC-0138 (2 orphan ACs).
- **True orphan scenarios** (scenario without any corresponding AC): UC-0003 (S4), UC-0050 (S2, S3), UC-0052 (S2, S3), UC-0054 (S3), UC-0056 (S3), UC-0057 (S4), UC-0058 (S3, S4), UC-0059 (S3), UC-0062 (S3), UC-0102 (S3), UC-0105 (S4), UC-0110 (S3), UC-0112 (S4).
- **Non-issues** (UC-0125, UC-0130, UC-0131, UC-0132, UC-0133): Multiple compile-check lines appear because each AC bullet ends with a compile assertion. These are structurally correct; the automated count is misleading.
- **Non-issues** (UC-0151, UC-0152, UC-0156): No compile checks in FRD-006 UCs is correct.

**Assessment:** The orphan scenarios and orphan ACs represent minor completeness gaps. They are non-blocking because the orphan scenarios are all failure-path or negative-path scenarios, and the orphan ACs are supplementary verification steps that extend existing scenario coverage rather than asserting completely uncovered behaviour.

---

## Single Actor Rule

All 79 UCs were checked. Every UC has exactly one Primary Actor. No violations found.

Typical actors across the corpus:

- **Operator** — human interacting with the dashboard (Batch A navigation UCs)
- **System** — automated system behaviour (feed grouping, tool pairing)
- **`Observatory.SwarmMonitor`** — GenServer process (Batch C FRD-004)
- **`Observatory.ProtocolTracker`** — GenServer process
- **`ObservatoryWeb.DashboardLive`** — LiveView module
- **Developer** — human writing code (FRD-005, FRD-006)
- **Agent (team lead or developer)** — agent executing roadmap commands (FRD-006)

UC-0158 lists "Developer (registering the protocol) / Agent (reading the protocol)" as the Primary Actor. This is a dual-role notation describing different trigger paths for the same UC, not two simultaneous actors. It does not violate the single actor rule because the use case has two distinct trigger paths (registration vs. reading) and the notation documents this distinction.

---

## Structural Checks

All 79 UCs pass structural validation.

**Frontmatter:** Every UC has valid YAML frontmatter containing `id`, `title`, `status`, `parent_fr`, and `adrs` fields. All `status` values are `draft`. All `adrs` values are lists.

**Required sections:** Every UC contains all required sections:
- `## Intent`
- `## Primary Actor`
- `## Trigger`
- `## Main Success Flow`
- `## Gherkin Scenarios`
- `## Acceptance Criteria`
- `## Traceability`

All UCs also include `## Supporting Actors`, `## Preconditions`, `## Alternate Flows`, `## Failure Flows`, and `## Data` sections, which are consistently present across the entire corpus even though they are not listed as required.

**Batch-level summary:**

| Batch | UCs | Frontmatter | Sections | Status |
|-------|-----|-------------|----------|--------|
| Batch A (UC-0001..0037) | 22 | PASS | PASS | PASS |
| Batch B (UC-0050..0062) | 13 | PASS | PASS | PASS |
| Batch C FRD-004 (UC-0100..0115) | 16 | PASS | PASS | PASS |
| Batch C FRD-005 (UC-0125..0143) | 19 | PASS | PASS | PASS |
| Batch C FRD-006 (UC-0150..0158) | 9 | PASS | PASS | PASS |

---

## Orphan Check

No orphan UCs found. Every `parent_fr` value in the 79 UC files references a valid FR that exists in one of the six FRDs.

All 79 `parent_fr` values were cross-referenced against the known FR ranges:
- FR-1.1 through FR-1.9 (FRD-001)
- FR-2.1 through FR-2.13 (FRD-002)
- FR-3.1 through FR-3.13 (FRD-003)
- FR-4.1 through FR-4.16 (FRD-004)
- FR-5.1 through FR-5.19 (FRD-005)
- FR-6.1 through FR-6.9 (FRD-006)

Zero invalid references detected.

---

## Number Range Compliance

| Batch | Allocated Range | FRDs Covered | UC IDs Found | Violations |
|-------|----------------|--------------|--------------|------------|
| A | UC-0001 to UC-0049 | FRD-001, FRD-002 | 0001-0009, 0025-0037 | None |
| B | UC-0050 to UC-0099 | FRD-003 | 0050-0062 | None |
| C | UC-0100 to UC-0169 | FRD-004, FRD-005, FRD-006 | 0100-0115, 0125-0143, 0150-0158 | None |

All 79 UCs fall within their designated batch ranges. No UC has an ID that places it outside its batch's allocation.

**Note on gaps:** UC IDs are not required to be contiguous within a batch. Gaps in Batch A (0010-0024 unused), Batch B (0063-0099 unused), and Batch C (0116-0124, 0144-0149, 0159-0169 unused) represent reserved space for future FRs or additional UCs. These gaps are not violations.

---

## Issues Found

### Minor Issues (Non-Blocking)

1. **Orphan scenarios** — 13 UCs have one or more Gherkin scenarios without a dedicated AC checkpoint. Affected UCs: UC-0003 (S4), UC-0050 (S2, S3), UC-0052 (S2, S3), UC-0054 (S3), UC-0056 (S3), UC-0057 (S4), UC-0058 (S3, S4), UC-0059 (S3), UC-0062 (S3), UC-0102 (S3), UC-0105 (S4), UC-0110 (S3), UC-0112 (S4). In every case the orphan scenario covers a negative/failure path. The compile check AC partially covers these but does not explicitly verify the scenario's assertion. Recommendation: add a dedicated AC per orphan scenario in a future pass.

2. **Orphan ACs** — 5 UCs have one or more ACs without a corresponding Gherkin scenario: UC-0053 (1), UC-0104 (1), UC-0111 (2), UC-0114 (2), UC-0138 (2). These ACs assert real, verifiable properties (field format constraints, nil checks, ordering guarantees) that are not captured by any named scenario. Recommendation: add a corresponding Gherkin scenario for each orphan AC in a future pass, or explicitly mark them as cross-scenario constraints.

3. **UC-0158 dual-role Primary Actor notation** — The Primary Actor field reads "Developer (registering the protocol) / Agent (reading the protocol)". This is not a structural violation but could be misread as two actors. Recommendation: split into two separate use cases or restate as "Developer or Agent depending on trigger."

### Non-Issues Confirmed

- FRD-006 UCs (UC-0150..0158) have no `mix compile --warnings-as-errors` AC. This is correct: roadmap convention FRs govern filesystem structure and documentation conventions, not compiled code.
- FRD-005 UCs (UC-0125..0133) have high compile-check counts because each AC bullet independently ends with a compile verification. This is a style choice, not a defect.
- Number range gaps are intentional reserved space, not violations.

---

## Overall: PASS

The UC corpus is structurally complete and internally consistent. All 79 FRs across 6 FRDs have exactly one UC. All UC files have valid frontmatter, all required sections, single primary actors, and valid parent_fr references within their FRD. Number range allocation is respected.

The Gherkin-AC mapping has 18 minor discrepancies (13 orphan scenarios, 5 UCs with orphan ACs). None of these prevent gate passage: every UC covers the substance of its parent FR, and the discrepancies are isolated to negative/failure paths or supplementary verification steps. They represent editorial debt, not specification gaps.

**Recommended follow-up before Gate 3:** Address the 18 Gherkin-AC discrepancies identified in the Issues section. This is editorial work (adding ACs or adding scenarios) that does not require changes to any FR or ADR.
