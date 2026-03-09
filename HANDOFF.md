# ICHOR IV (formerly Observatory) - Handoff

## Current Status: Archon Memories Integration + Space Concept (2026-03-09)

### Just Completed

1. **Space attribute** (in `/Users/xander/code/www/memories`):
   - Added `space` string attribute to Episode, Entity, Fact resources
   - Format: lowercase, colon-separated (e.g. `general`, `project:ichor`, `project:ichor:archon`)
   - Default: `"general"`, validated with regex
   - Propagated through DigestEpisode pipeline (LoadContext -> PersistEntities/PersistFacts)
   - Added space filter to VectorChord SQL WHERE clauses (all 3 search modes)
   - Wired through SearchVector, Client.Local, GraphController, Episode :search action
   - DB indexes on `[:group_id, :space]` for all 3 tables
   - Episode identity updated to `[:group_id, :user_id, :space, :content_hash]`

2. **Episode type/source enum realignment** (Zep-aligned):
   - `type` = structural: `:text` (narrative), `:message` (conversation), `:json` (structured)
   - `source` = provenance: `:user`, `:agent`, `:system`, `:document`, `:api`
   - Data migration converted existing records (observation->text, event->json, etc.)
   - Defaults: type `text`, source `api` (HTTP ingest), Archon uses source `agent`

3. **Observatory Archon wiring updated**:
   - MemoriesClient: passes `space` on search/ingest, uses new type/source values
   - Tools.Memory: all 3 tools accept optional `space` argument

### Prior: Memories Integration (earlier this session)
- MemoriesClient HTTP client, 3 Memory Ash tools, 10 tools total in Archon.Tools
- 5 bugs fixed in Memories search pipeline (reranker, SearchVector, embeddings, hydration, group_id)

### Prior: AgentRegistry Decomposition
- AgentRegistry 669 -> 293 lines + 5 submodules (AgentEntry, EventHandler, IdentityMerge, TeamSync, Sweep)

### Next Steps (ordered)

1. **Archon LLM wiring** -- connect Archon to Claude API with AshAi tools
2. **Archon chat UI** -- dashboard drawer/panel for conversing with Archon
3. **AgentSpawner refactor** -- 318 lines, over 200-line limit

### Memories Server
- Running on port 4000 (must be running for Archon memory tools)
- Requires Docker: postgres (port 5434) + falkordb (port 6379)
- ONNX models on external drive: `/Volumes/T5/models/ONNX`
- After code changes, server must be restarted (Reactor steps don't auto-reload)

### Build Status
Both projects: `mix compile --warnings-as-errors` clean.
