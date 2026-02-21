# Gate 2: UC Completeness Report
# ARCHITECTS IV HYPERVISOR OBSERVATORY — Mode B Pipeline

**Result: PASS**
**Date:** 2026-02-22

---

## Counts

| Metric | Count |
|--------|-------|
| Total FRDs | 7 |
| Total FRs | 78 |
| Total UCs | 79 |

FRD breakdown:
- FRD-006: 9 FRs (FR-6.1 – FR-6.9)
- FRD-007: 9 FRs (FR-7.1 – FR-7.9)
- FRD-008: 13 FRs (FR-8.1 – FR-8.13)
- FRD-009: 11 FRs (FR-9.1 – FR-9.11)
- FRD-010: 12 FRs (FR-10.1 – FR-10.12)
- FRD-011: 11 FRs (FR-11.1 – FR-11.11)
- FRD-012: 13 FRs (FR-12.1 – FR-12.13)

---

## Check 1: FR Coverage

**PASS**

All 78 FRs have at least one UC with a matching `parent_fr:` frontmatter value. No uncovered FRs.

Note: FR-12.11 has two UCs (UC-0310 and UC-0311), which is permitted.

---

## Check 2: Single Primary Actor

**PASS**

All 79 UCs have exactly one `## Primary Actor` section.

---

## Check 3: Gherkin–AC Mapping

**PASS**

All 79 UCs have identical `Scenario:` counts and `- [ ] mix test` AC counts.

| UC | parent_fr | Scenarios | Test ACs |
|----|-----------|-----------|----------|
| UC-0200 | FR-6.1 | 2 | 2 |
| UC-0201 | FR-6.2 | 3 | 3 |
| UC-0202 | FR-6.3 | 3 | 3 |
| UC-0203 | FR-6.4 | 3 | 3 |
| UC-0204 | FR-6.5 | 3 | 3 |
| UC-0205 | FR-6.6 | 3 | 3 |
| UC-0206 | FR-6.7 | 2 | 2 |
| UC-0207 | FR-6.8 | 3 | 3 |
| UC-0208 | FR-6.9 | 3 | 3 |
| UC-0209 | FR-7.1 | 2 | 2 |
| UC-0210 | FR-7.2 | 3 | 3 |
| UC-0211 | FR-7.3 | 3 | 3 |
| UC-0212 | FR-7.4 | 3 | 3 |
| UC-0213 | FR-7.5 | 3 | 3 |
| UC-0214 | FR-7.6 | 3 | 3 |
| UC-0215 | FR-7.7 | 3 | 3 |
| UC-0216 | FR-7.8 | 3 | 3 |
| UC-0217 | FR-7.9 | 3 | 3 |
| UC-0230 | FR-8.1 | 2 | 2 |
| UC-0231 | FR-8.2 | 2 | 2 |
| UC-0232 | FR-8.3 | 2 | 2 |
| UC-0233 | FR-8.4 | 2 | 2 |
| UC-0234 | FR-8.5 | 2 | 2 |
| UC-0235 | FR-8.6 | 2 | 2 |
| UC-0236 | FR-8.7 | 2 | 2 |
| UC-0237 | FR-8.8 | 3 | 3 |
| UC-0238 | FR-8.9 | 2 | 2 |
| UC-0239 | FR-8.10 | 2 | 2 |
| UC-0240 | FR-8.11 | 3 | 3 |
| UC-0241 | FR-8.12 | 2 | 2 |
| UC-0242 | FR-9.1 | 2 | 2 |
| UC-0243 | FR-9.3 | 2 | 2 |
| UC-0244 | FR-9.5 | 3 | 3 |
| UC-0245 | FR-9.7 | 2 | 2 |
| UC-0246 | FR-9.8 | 3 | 3 |
| UC-0247 | FR-9.10 | 3 | 3 |
| UC-0248 | FR-9.11 | 2 | 2 |
| UC-0249 | FR-8.13 | 2 | 2 |
| UC-0250 | FR-9.2 | 2 | 2 |
| UC-0251 | FR-9.4 | 2 | 2 |
| UC-0252 | FR-9.6 | 2 | 2 |
| UC-0253 | FR-9.9 | 2 | 2 |
| UC-0260 | FR-10.1 | 3 | 3 |
| UC-0261 | FR-10.2 | 2 | 2 |
| UC-0262 | FR-10.3 | 2 | 2 |
| UC-0263 | FR-10.4 | 2 | 2 |
| UC-0264 | FR-10.5 | 2 | 2 |
| UC-0265 | FR-10.6 | 2 | 2 |
| UC-0266 | FR-10.7 | 2 | 2 |
| UC-0267 | FR-10.10 | 2 | 2 |
| UC-0268 | FR-10.9 | 2 | 2 |
| UC-0269 | FR-10.11 | 2 | 2 |
| UC-0270 | FR-10.12 | 2 | 2 |
| UC-0271 | FR-11.1 | 3 | 3 |
| UC-0272 | FR-11.2 | 3 | 3 |
| UC-0273 | FR-11.3 | 2 | 2 |
| UC-0274 | FR-11.4 | 3 | 3 |
| UC-0275 | FR-11.7 | 2 | 2 |
| UC-0276 | FR-11.9 | 2 | 2 |
| UC-0277 | FR-11.10 | 3 | 3 |
| UC-0278 | FR-11.11 | 2 | 2 |
| UC-0279 | FR-10.8 | 3 | 3 |
| UC-0280 | FR-11.5 | 3 | 3 |
| UC-0281 | FR-11.6 | 3 | 3 |
| UC-0282 | FR-11.8 | 3 | 3 |
| UC-0300 | FR-12.1 | 2 | 2 |
| UC-0301 | FR-12.2 | 2 | 2 |
| UC-0302 | FR-12.3 | 3 | 3 |
| UC-0303 | FR-12.4 | 3 | 3 |
| UC-0304 | FR-12.5 | 2 | 2 |
| UC-0305 | FR-12.6 | 2 | 2 |
| UC-0306 | FR-12.7 | 2 | 2 |
| UC-0307 | FR-12.8 | 3 | 3 |
| UC-0308 | FR-12.9 | 3 | 3 |
| UC-0309 | FR-12.10 | 3 | 3 |
| UC-0310 | FR-12.11 | 3 | 3 |
| UC-0311 | FR-12.11 | 2 | 2 |
| UC-0312 | FR-12.12 | 3 | 3 |
| UC-0313 | FR-12.13 | 3 | 3 |

---

## Check 4: Orphan parent_fr References

**PASS**

All 79 `parent_fr:` values resolve to FR IDs that exist in the FRDs.

---

## Check 5: Status Field

**PASS**

All 79 UCs have `status: draft` in their frontmatter.

---

## Summary

| Check | Result |
|-------|--------|
| Check 1: FR Coverage | PASS |
| Check 2: Single Primary Actor | PASS |
| Check 3: Gherkin–AC Mapping | PASS |
| Check 4: Orphan parent_fr | PASS |
| Check 5: Status Field | PASS |

**Overall: PASS**

7 FRDs · 78 FRs · 79 UCs — Mode B complete.
