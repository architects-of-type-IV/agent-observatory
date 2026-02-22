# Gate 1 Report: FRD Coverage and FR Consistency

**Date:** 2026-02-21
**Result:** FAIL

---

## ADR Coverage

Each ADR must appear in at least one FRD's `source_adr` frontmatter field.

| ADR | Covered by FRD (frontmatter) | Status |
|-----|------------------------------|--------|
| ADR-001 | FRD-001 | PASS |
| ADR-002 | FRD-002 | PASS |
| ADR-003 | FRD-001 | PASS |
| ADR-004 | FRD-003 | PASS |
| ADR-005 | FRD-003 | PASS |
| ADR-006 | FRD-005 | PASS |
| ADR-007 | FRD-004 | PASS |
| ADR-008 | FRD-001 | PASS |
| ADR-009 | FRD-006 | PASS |
| ADR-010 | FRD-005 | PASS |
| ADR-011 | FRD-005 | PASS |
| ADR-012 | FRD-005 | PASS |

**Orphan ADRs:** None. All 12 ADRs have at least one FRD covering them via `source_adr` frontmatter.

---

## FR Consistency

| FRD | FR Count | Sequential | Pos/Neg Paths | source_adr Match | Status |
|-----|----------|------------|---------------|------------------|--------|
| FRD-001 | 9 (FR-1.1 to FR-1.9) | PASS | PASS | PASS | PASS |
| FRD-002 | 13 (FR-2.1 to FR-2.13) | PASS | PASS | PASS | PASS |
| FRD-003 | 13 (FR-3.1 to FR-3.13) | PASS | PASS | PASS | PASS |
| FRD-004 | 16 (FR-4.1 to FR-4.16) | PASS | PASS | FAIL | FAIL |
| FRD-005 | 19 (FR-5.1 to FR-5.19) | PASS | PASS | PASS | PASS |
| FRD-006 | 9 (FR-6.1 to FR-6.9) | PASS | PASS | FAIL | FAIL |

### FRD-004 source_adr mismatch detail

- **Frontmatter `source_adr`:** `[ADR-007]`
- **Related ADRs section (body):** ADR-007, ADR-001, ADR-005
- **Discrepancy:** ADR-001 and ADR-005 are listed in the body's Related ADRs section but absent from the `source_adr` frontmatter field.

### FRD-006 source_adr mismatch detail

- **Frontmatter `source_adr`:** `[ADR-009]`
- **Related ADRs section (body):** ADR-009, ADR-011
- **Discrepancy:** ADR-011 is listed in the body's Related ADRs section but absent from the `source_adr` frontmatter field.

---

## Cross-FRD Collisions

Each FRD uses a distinct FR prefix number:

| FRD | FR Prefix |
|-----|-----------|
| FRD-001 | FR-1.* |
| FRD-002 | FR-2.* |
| FRD-003 | FR-3.* |
| FRD-004 | FR-4.* |
| FRD-005 | FR-5.* |
| FRD-006 | FR-6.* |

No two FRDs share the same FR prefix. **PASS.**

---

## Structural Checks

| FRD | Valid Frontmatter (id, title, date, status, source_adr) | ## Purpose | ## Functional Requirements | ## Related ADRs | Status |
|-----|--------------------------------------------------------|------------|---------------------------|-----------------|--------|
| FRD-001 | PASS | PASS | PASS | PASS | PASS |
| FRD-002 | PASS | PASS | PASS | PASS | PASS |
| FRD-003 | PASS | PASS | PASS | PASS | PASS |
| FRD-004 | PASS | PASS | PASS | PASS | PASS |
| FRD-005 | PASS | PASS | PASS | PASS | PASS |
| FRD-006 | PASS | PASS | PASS | PASS | PASS |

All 6 FRDs have well-formed YAML frontmatter with all required fields, and all three required sections are present. **PASS.**

---

## Issues Found

1. **FRD-004 `source_adr` incomplete** -- The frontmatter lists only `[ADR-007]` but the body's Related ADRs section references ADR-001 and ADR-005 as well. Both ADR-001 and ADR-005 are substantively referenced in FRD-004: ADR-001 is cited in the purpose narrative and Related ADRs section ("defines the UI that consumes SwarmMonitor and ProtocolTracker data"), and ADR-005 is cited in the Related ADRs section ("establishes ETS as the storage medium for ProtocolTracker traces"). The `source_adr` frontmatter field must be updated to `[ADR-007, ADR-001, ADR-005]` to reflect all authoritative sources.

2. **FRD-006 `source_adr` incomplete** -- The frontmatter lists only `[ADR-009]` but the body's Related ADRs section references ADR-011 as well ("Handler Delegation Pattern; shares the same sprint origin as ADR-009"). The `source_adr` frontmatter field must be updated to `[ADR-009, ADR-011]` to be consistent with the body.

---

## Overall: FAIL

Two FRDs have `source_adr` frontmatter fields that do not match the ADRs referenced in their own Related ADRs sections:

- FRD-004: frontmatter missing ADR-001 and ADR-005
- FRD-006: frontmatter missing ADR-011

All other checks pass: no orphan ADRs, all FR numbering is sequential with no gaps or duplicates, all FRs have both positive and negative paths, no cross-FRD FR prefix collisions, and all structural sections are present in every FRD. Resolve the two `source_adr` mismatches and re-run Gate 1.
