# First-Class DAG Abstraction for ICHOR

**Date:** 2026-03-22
**Status:** Research / brainstorming

## The Problem

ICHOR claims to have DAGs in two places:

1. **tasks.jsonl** -- JSONL file with `blocked_by` string arrays, parsed by `jq`
2. **Ash tasks in DB** -- task records with status fields, no graph relationships

Neither is a real DAG. The graph structure is implicit -- it exists only when `jq` or application code reconstructs it from flat data. No layer enforces acyclicity, referential integrity, or edge semantics. The "DAG" is an emergent property of text parsing, not a structural guarantee.

### What a real DAG gives you

A DAG is a directed graph with no directed cycles. It encodes **partial ordering with causality** -- "A must happen before C, B must happen before C, but A and B have no ordering relationship." This is inherently parallel, and the DAG makes that explicit.

DAGs appear throughout computer science:
- Git commits (merge parents, no cycles)
- Build systems (Make, Bazel -- target dependencies)
- Workflow orchestration (Airflow, Attractor -- task pipelines)
- Compilers (SSA form, data flow analysis)
- Causal inference (which events can influence which)
- Blockchain (transaction ordering)

### What we lose without one

| Concern | Current state | With real DAG |
|---|---|---|
| Cycle prevention | Hope / manual review | Structural guarantee |
| Referential integrity | Typo in `blocked_by` silently breaks | Can't reference nonexistent node |
| Edge semantics | String in an array | Typed, validated relationships |
| Traversal | jq filter chain | Graph algorithm |
| Visualization | Manual trace of `blocked_by` chains | Render directly (DOT, Mermaid, Canvas) |
| Parallel discovery | Orchestrator infers from absence of edges | Explicit from structure |
| Consistency | Two sources (file + DB), manual sync | Single source of truth |
| Semantic validation | Not possible | File overlap analysis, contract checking |

## Validation Layers

A real DAG abstraction must validate at four layers:

### Layer 1: Structural validity (is it a DAG?)
- No cycles (topological sort succeeds)
- No dangling references (every edge target exists)
- Every node is reachable from a root
- Every node can reach a terminal
- Detection: Kahn's algorithm -- repeatedly remove nodes with no incoming edges; if nodes remain, they form a cycle

### Layer 2: Consistency (do representations agree?)
- tasks.jsonl says A blocks B -- does the DB agree?
- DB says task X is complete -- does the file reflect that?
- Drift detection: which source diverged, and when?
- Goal: single source of truth eliminates this layer entirely

### Layer 3: Semantic validity (is the DAG true?)
- Does B actually use A's output, or is the dependency theatrical?
- Could B run without A and still succeed? (false dependency = unnecessary serialization)
- Does B depend on C but not declare it? (missing edge = race condition)
- Detection methods:
  - **File overlap analysis**: tasks touching same files without an edge = missing dependency
  - **Runtime validation**: run B without A; if it succeeds, the edge is false
  - **Output/input contract checking**: A produces X, B consumes X; if B doesn't read X, the edge is decorative

### Layer 4: Temporal validity (did execution match the DAG?)
- After a pipeline runs, compare actual execution order against declared DAG
- If B ran before A despite the edge, the orchestrator violated the contract
- Audit trail: timestamp every state transition, verify partial order was respected

## Design Space

### Where should the DAG live?

**Option A: Ash Resource with self-referential relationships**

The DAG is an Ash resource. Nodes are task records. Edges are `belongs_to`/`has_many` relationships (or a join table). Ash validations enforce acyclicity. The database is the single source of truth. tasks.jsonl becomes an import/export format.

Pros:
- Aligns with existing architecture (Ash is authoritative)
- Referential integrity from the database
- Queryable (find all ready tasks, find critical path, find orphans)
- Validations are declarative Ash changes

Cons:
- SQLite limitations (no recursive CTEs for transitive closure -- or can it?)
- Cycle detection in a change/validation may be expensive for large graphs
- tasks.jsonl interop requires sync logic

**Option B: In-memory graph structure (ETS or process state)**

A GenServer or ETS table holds the graph as an adjacency list. Validated on construction. Persisted to DB or file on checkpoint.

Pros:
- Fast traversal and mutation
- Graph algorithms run in-memory
- No database round-trips for scheduling decisions

Cons:
- Volatile (must be rebuilt from persistent store on restart)
- Adds a process (potential bottleneck if serialized)
- Dual-write problem with DB

**Option C: Hybrid -- Ash for persistence, ETS for runtime**

Ash resource stores the canonical graph. On pipeline start, load into an ETS-backed graph structure for fast traversal. Write-back on state transitions.

Pros:
- Best of both: persistence + speed
- Ash handles validation and queries
- ETS handles scheduling hot path

Cons:
- Complexity of keeping two representations in sync
- Must handle crash recovery (ETS is volatile)

**Option D: Elixir's `:digraph` module**

Erlang/OTP ships with `:digraph` -- an ETS-backed directed graph implementation. Supports cycle detection, topological sort, shortest path, connected components.

```elixir
g = :digraph.new([:acyclic])  # raises on cycle insertion
:digraph.add_vertex(g, "task-1")
:digraph.add_vertex(g, "task-2")
:digraph.add_edge(g, "task-1", "task-2")  # task-1 blocks task-2
:digraph_utils.topsort(g)  # => ["task-1", "task-2"]
:digraph_utils.is_acyclic(g)  # => true
```

The `:acyclic` option makes cycle prevention a structural guarantee -- `:digraph.add_edge/3` returns `{:error, {:bad_edge, path}}` if the edge would create a cycle.

Pros:
- Ships with OTP, zero dependencies
- ETS-backed, fast
- Cycle prevention built in
- Topological sort, reachability, connected components all provided
- Battle-tested (used internally by the compiler, `mix`)

Cons:
- Mutable ETS state (not functional)
- Must be wrapped for persistence
- No built-in serialization

### Serialization format

How should DAGs be represented externally?

| Format | Authoring | Generation | Visualization | Tooling |
|---|---|---|---|---|
| **DOT (Graphviz)** | Good (visual language) | Easy to generate | Native (Graphviz, d3-graphviz) | Mature ecosystem |
| **tasks.jsonl** | Familiar | Current format | Requires conversion | jq |
| **Mermaid** | Markdown-native | Easy to generate | GitHub/docs render natively | Growing |
| **Adjacency list JSON** | Awkward for humans | Natural for code | Requires conversion | Standard |
| **Elixir term** | For developers only | Native | None | Mix tasks |

Multiple formats can coexist if there's a canonical internal representation. Generate DOT/Mermaid for visualization, accept tasks.jsonl for import, store in Ash for persistence.

## Open Questions

1. **Should the DAG be a separate Ash Domain or part of Factory?**
   - Factory already owns project/pipeline execution
   - A separate `Ichor.Graph` domain could be reusable beyond task pipelines

2. **What are the node and edge types?**
   - Attractor uses DOT shapes (box=LLM, hexagon=human, diamond=conditional)
   - Our tasks have implicit types -- should edges be typed too? (blocks, informs, produces)

3. **How does this interact with the Sandbox Manager?**
   - The DAG scheduler decides WHAT runs next
   - The Sandbox Manager decides WHERE it runs
   - Clean separation or tight coupling?

4. **Can `:digraph` with `:acyclic` option serve as the runtime representation?**
   - Wrap in a GenServer for named access
   - Persist to Ash on state transitions
   - Rebuild from Ash on startup

5. **What about the session history DAG?**
   - Conversation mining (decisions, workflows) could use the same abstraction
   - Nodes = decisions/patterns, edges = "led to", "contradicted", "refined"
   - Same graph engine, different domain

6. **Edge conditions and routing**
   - Attractor puts conditions on edges (`outcome=success`)
   - Currently our routing is in the orchestrator's head
   - Should edges carry routing logic?

## References

- [Attractor spec](https://github.com/strongdm/attractor) -- DOT-based pipeline orchestration
- [Container & MicroVM Research](containers.md) -- sandbox infrastructure
- [Kubernetes Sandboxing Research](kubernetes-sandboxing.md) -- K8s agent sandboxing
- [Sandboxed Teams Design](../specs/2026-03-21-sandboxed-teams-design.md) -- sandbox provider architecture
- Erlang `:digraph` module -- OTP's built-in directed graph
- Erlang `:digraph_utils` -- topological sort, cycle detection, reachability
- Ash Reactor -- has digraph built in; may understand Ash domain model natively
