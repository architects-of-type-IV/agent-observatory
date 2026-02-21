---
id: FRD-001
title: Episode Resource Functional Requirements
date: 2026-02-19
status: active
source_adr: [ADR-000, ADR-028]
---

# FRD-001: Episode Resource

## Purpose

The Episode resource is the raw input store for all memory ingestion. It preserves original content for provenance and is the source of truth from which all entities and facts are extracted. Every episode belongs to a user within a tenant, making it the foundational cross-domain resource that links `Memories.Accounts` to `Memories.API`.

## Functional Requirements

### FR-1.1: Tenant Isolation via group_id

The system MUST scope every episode to a `group_id` using the Ash attribute multitenancy strategy.

**Positive path**: When an episode is created or queried with a `group_id` set as tenant, the system returns only episodes belonging to that tenant.

**Negative path**: When a query is executed without a `group_id` tenant set, the system MUST reject the operation -- no cross-tenant data may be returned.

### FR-1.2: group_id is Non-Nullable

The system MUST require `group_id` to be present and non-null on every episode record.

**Positive path**: When an episode is created with a valid `group_id` string, the record is persisted with that tenant identifier.

**Negative path**: When an episode is created with a null or missing `group_id`, the system MUST reject the changeset with a validation error.

### FR-1.3: User Ownership is Required

The system MUST require every episode to belong to a `Memories.Accounts.User` via `user_id`.

**Positive path**: When an episode is created with a valid `user_id` referencing an existing `Accounts.User`, the record is persisted with that ownership.

**Negative path**: When an episode is created without a `user_id`, the system MUST reject the changeset -- episodes cannot exist without a user.

### FR-1.4: Source Classification

The system MUST require a `source` attribute that classifies the episode content type as one of: `message`, `text`, `json`, `document`.

**Positive path**: When an episode is created with one of the four valid source values, the record is persisted with that classification.

**Negative path**: When an episode is created with a `source` value outside the allowed enum, the system MUST reject the changeset with a validation error.

### FR-1.5: Optional Source Description

The system MAY store an optional `source_description` string that provides context about where the episode originated.

**Positive path**: When a `source_description` is provided on create, the system persists it alongside the episode.

**Negative path**: When `source_description` is omitted, the system MUST accept the record without error -- this field is optional.

### FR-1.6: Content Storage

The system MUST store the raw episode content in a `content` text field.

**Positive path**: When an episode is created with content, the system persists the full original content without modification.

**Negative path**: When content is omitted and the system requires it for hash computation, the system MUST reject or produce a null hash -- no silent truncation or transformation of content is permitted.

### FR-1.7: Content Hash Auto-Computation

The system MUST auto-compute a SHA256 `content_hash` from the episode content on create.

**Positive path**: When an episode is created, the system automatically computes and stores the SHA256 hash of the content without requiring the caller to supply it.

**Negative path**: When a caller attempts to supply a pre-computed `content_hash` that does not match the content, the system MUST NOT use the caller-supplied value -- the hash is always system-computed.

### FR-1.8: Content Hash Idempotency

The system MUST use the identity `(group_id, user_id, content_hash)` as the upsert key for episode creation.

**Positive path**: When an episode is submitted with a `(group_id, user_id, content_hash)` tuple that already exists, the system returns the existing episode without creating a duplicate.

**Negative path**: When identical content is submitted twice under the same user and tenant, the system MUST NOT create two episode records -- the second submission must resolve to the first.

### FR-1.9: Content Embedding

The system MUST store a `content_embedding` as a 1024-dimensional vector for semantic search.

**Positive path**: When a content embedding is provided, the system persists it in the VectorChord-indexed column for later similarity queries.

**Negative path**: When no embedding is provided on create, the system MUST accept the record with a null embedding -- embedding population is a later pipeline step and must not block ingestion.

### FR-1.10: valid_at Timestamp

The system MUST store a `valid_at` datetime representing when the episode occurred in world time (as opposed to when the system recorded it).

**Positive path**: When a `valid_at` value is supplied, the system persists it as the world-time timestamp for the episode.

**Negative path**: When `valid_at` is absent, the system MUST either reject the record or apply a documented default -- the field must not be silently ignored.

### FR-1.11: created_at Timestamp

The system MUST auto-populate a `created_at` datetime representing when the system ingested the episode.

**Positive path**: When an episode is created, the system sets `created_at` to the current system time automatically.

**Negative path**: When a caller attempts to supply a `created_at` value, the system MUST NOT accept it -- this field is system-controlled.

### FR-1.12: UUIDv7 Primary Key

The system MUST use a UUIDv7 primary key (`id`) for every episode record.

**Positive path**: When an episode is created, the system generates and assigns a UUIDv7 as the primary key.

**Negative path**: When a caller attempts to supply an `id` value, the system MUST NOT accept it -- the primary key is system-generated.

### FR-1.13: Optional Name

The system MAY store an optional `name` string as a human-readable identifier for the episode.

**Positive path**: When a `name` is provided on create, the system persists it alongside the episode.

**Negative path**: When `name` is omitted, the system MUST accept the record without error -- this field is optional.

### FR-1.14: PostgreSQL as Write Source of Truth

The system MUST write all episode data to PostgreSQL (via VectorChord) as the primary store before any derived store is updated.

**Positive path**: When an episode is created, the record is committed to PostgreSQL and the response is returned before any downstream sync operations occur.

**Negative path**: When the PostgreSQL write fails, the system MUST NOT consider the episode created -- no downstream sync or workflow may proceed on a failed write.

### FR-1.15: group_id B-tree Index

The system MUST maintain a B-tree index on `group_id` to support efficient multi-tenancy filtering.

**Positive path**: When episodes are queried by tenant, the B-tree index on `group_id` is used to filter results without full table scans.

**Negative path**: When the index is absent, tenant-scoped queries MUST NOT silently return cross-tenant data -- the absence is a deployment error, not a runtime behavior to accommodate.

### FR-1.16: Content Embedding VectorChord Index

The system MUST maintain a VectorChord HNSW index on `content_embedding` for semantic similarity search.

**Positive path**: When a similarity query is issued against episode embeddings, the HNSW index is used to return approximate nearest neighbors efficiently.

**Negative path**: When the embedding column is null for a record, the system MUST NOT include that record in similarity search results -- null embeddings are not indexed.

### FR-1.17: Content GIN Full-Text Index

The system MUST maintain a GIN tsvector index on `content` for BM25 keyword search.

**Positive path**: When a keyword search is issued against episode content, the GIN index enables efficient full-text retrieval.

**Negative path**: When the index is absent, keyword queries MUST NOT return silent empty results -- the absence is a deployment error.

## Out of Scope (Phase 1)

- Embedding computation (performed in a downstream workflow step, not the Episode resource itself)
- Episode retrieval and search APIs (Phase 3)
- Episode expiry and soft-delete
- Thread and Message types (deferred to future ADRs)
- Space scoping within tenants (deferred -- ADR-007)
- Actor-based authorization (authentication is future; current pattern is tenant-set-at-call-site)

## Related ADRs

- [ADR-000](../decisions/ADR-000-unified-schema.md) -- Unified Schema: canonical field names, identity constraint, indexing strategy, storage architecture
- [ADR-028](../decisions/ADR-028-authentication.md) -- Authentication and Multi-tenancy: group_id attribute strategy, user_id requirement, cross-domain architecture
