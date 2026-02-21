---
id: FRD-NNN
title: <Resource/Subsystem Name> Functional Requirements
date: YYYY-MM-DD
status: draft
source_adr: [ADR-NNN]
related_rule: []
---

# FRD-NNN: <Resource/Subsystem Name>

## Purpose

<1-2 paragraphs describing what this resource or subsystem is, its role in the
system, and which ADRs govern its design. State the authoritative ADR for any
field-level conflicts.>

## Functional Requirements

### FR-N.1: <Requirement Title>

<One paragraph stating the requirement using RFC 2119 language (MUST/MUST NOT/MAY/SHOULD).
Be specific about field names, types, constraints, and module paths.>

**Positive path**: <What happens when the requirement is correctly satisfied.
Describe the expected system behavior with concrete values or examples.>

**Negative path**: <What happens when the requirement is violated. Describe the
error behavior: rejection, validation error, non-conformance declaration, or
silent acceptance if the field is optional.>

---

### FR-N.2: <Next Requirement Title>

<Requirement statement.>

**Positive path**: <Expected behavior.>

**Negative path**: <Violation behavior.>

---

<!-- Repeat FR blocks as needed. Number sequentially: FR-N.1, FR-N.2, ... FR-N.M -->

## Out of Scope (Phase 1)

- <Deferred capability> (<Phase or ADR reference>)
- <Deferred capability> (<Phase or ADR reference>)

## Related ADRs

- [ADR-NNN](../decisions/ADR-NNN-name.md) -- <Brief note on what this ADR contributes to this FRD>
- [ADR-NNN](../decisions/ADR-NNN-name.md) -- <Brief note>
