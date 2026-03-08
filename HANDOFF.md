# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Archon Memories Integration (2026-03-09)

### Just Completed

1. **Memories project fixes** (in `/Users/xander/code/www/memories`):
   - Fixed `:rrf` reranker dispatch bug -- shorthand atoms now mapped to modules in `extract_backend/1`
   - Fixed `SearchVector` step -- now searches all 3 tables (episodes, graph_nodes, graph_edges), not just episodes
   - Added entity embedding step (`EmbedEntities`, Step 4.5) to DigestEpisode pipeline
   - Added fact embedding step (`EmbedFacts`, Step 5.7) to DigestEpisode pipeline
   - Added `:set_embedding` update actions to Entity and Fact resources
   - Added `:embedding` to `persist_entity` accept list
   - Added result hydration in `Client.Local` -- search now returns full entity/fact/episode data, not just IDs
   - Fixed `resolve_group_id` to prefer explicit `group_id` over `user_id`/`graph_id`
   - Added `group_id` pass-through in `GraphController.parse_search_opts`

2. **Observatory Archon integration**:
   - `Observatory.Archon.MemoriesClient` -- HTTP client for Memories API (search, ingest, query)
   - `Observatory.Archon.Tools.Memory` -- 3 Ash tools: search_memory, remember, query_memory
   - Wired into `Archon.Tools` domain (now 10 tools: 7 fleet + 3 memory)

3. **Archon namespace in Memories**:
   - Group UUID: `0f8eae17-15fc-5af1-8761-0093dc9b5027` (deterministic, v5 DNS)
   - User UUID: `8fe50fd6-f0da-5adc-9251-6417dc3092e8`
   - 3 episodes ingested, 13 entities + 9 facts extracted with embeddings

### Verified Working

- Episode ingest: `POST /api/episodes/ingest` -> 202, async digestion extracts entities/facts with embeddings
- Graph search: `POST /api/graph/search` -> 200, returns hydrated facts/entities/episodes with scores
- Full pipeline: embed query -> vector search (3 tables) -> BM25 -> graph -> RRF fusion -> rerank -> hydrate
- Observatory `MemoriesClient.search/2` and `MemoriesClient.ingest/2` working via HTTP

### Memories Server

- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
- After code changes, server must be restarted (Reactor steps don't auto-reload)

### Next Steps (ordered)

1. **"Space" concept** -- user wants extra namespacing on top of group_id (discussed but not implemented)
2. **Archon LLM wiring** -- connect Archon to Claude API with AshAi tools
3. **Archon chat UI** -- dashboard drawer/panel for conversing with Archon
4. **AgentSpawner refactor** -- 318 lines, over 200-line limit

### Remaining (backlog)
- Clustering config, remote tmux delivery
- Phase 8: ICHOR IV rename (deferred)

### Build Status
Both projects: `mix compile --warnings-as-errors` clean.
