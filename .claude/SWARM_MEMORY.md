# Swarm’s continuity layer, not as a chat-history archive.

A bi-temporal graph is valuable because it lets agents track not just facts and relationships, but also when those facts were true and when the system learned them; that is exactly the difference between “current belief,” “historical truth,” and “newly discovered correction.” Zep/Graphiti’s model is built around episodic data, entity/fact graphs, invalidation of prior facts, and retrieval that mixes semantic, lexical, and graph traversal for time-aware context.

Here is how the swarm should use it.

1. Shared long-term memory for all agents

Every agent should read from the graph before planning and write back after acting. That matches the core shape of temporal graph memory systems: episodic nodes store raw events, entity nodes capture stable things, and edges capture evolving facts/relationships over time.

Practical use:
	•	before a task: retrieve relevant entities, recent episodes, active facts, invalidated facts
	•	during a task: pin working context from the graph
	•	after a task: write episode summary, decisions, outcomes, contradictions, and discovered entities

2. Separate “what is true now” from “what was true before”

This is the first real advantage over ordinary vector memory. The swarm can answer:
	•	what is true now
	•	what was believed last week
	•	when a fact changed
	•	which agent introduced or corrected the fact

That matters for planning, debugging, audits, and coordination because fact invalidation is a first-class concept in temporal graph memory. 

Use cases:
	•	architecture decisions that changed over time
	•	customer/account state transitions
	•	project status evolution
	•	policy changes
	•	infrastructure topology changes
	•	agent role/history changes

3. Mission continuity across agent handoffs

Handoffs are where most multi-agent systems rot. Your graph should act as the canonical mission ledger:
	•	mission
	•	objective
	•	current phase
	•	unresolved questions
	•	blockers
	•	decisions made
	•	failed attempts
	•	next recommended actions

Zep’s graph context is designed to persist context across sessions and clients, which is exactly the property you want for cross-agent continuity.

Minimal pattern:
	•	agent A explores
	•	agent A writes episode + extracted facts + confidence
	•	agent B retrieves mission neighborhood
	•	agent B continues without rereading the whole world

4. Make the swarm query neighborhoods, not documents

Don’t ask the graph like a document store. Ask it like a living world model.

Useful retrieval shapes:
	•	entity-centered: “what do we know about customer X now?”
	•	timeline-centered: “what changed for system Y in the last 30 days?”
	•	contradiction-centered: “which facts about topic Z were invalidated recently?”
	•	relationship-centered: “what is connected to capability Q?”
	•	mission-centered: “what facts, decisions, and episodes are adjacent to objective M?”

This aligns with Graphiti/Zep’s graph retrieval model, which combines semantic search, full-text search, and graph traversal rather than relying only on embeddings.

5. Use episodes as raw truth, facts as compressed truth

A clean swarm pattern is:
	•	Episode layer: raw conversations, task runs, incidents, commits, workflows, observations
	•	Entity/fact layer: extracted, deduplicated, time-bound facts
	•	Community layer: clustered themes, domains, projects, categories

That mirrors the three-layer graph shape described for Zep/Graphiti: episodic nodes, semantic/entity relations, and higher-level communities. 

This gives the swarm three useful modes:
	•	exact replay from episodes
	•	efficient reasoning from facts
	•	strategic navigation from communities

6. Turn it into role memory, not just knowledge memory

The graph should store not only world facts, but swarm facts:
	•	which agents are good at what
	•	which teams solved what before
	•	which agents disagree often
	•	which agents produce reliable outputs
	•	which pairings work well
	•	which workflows usually fail

That gives you adaptive coordination. It is an inference on top of the graph model, but a grounded one: the graph is built to preserve evolving relationships and historical context, so agent-to-agent and agent-to-capability relationships fit naturally into the same structure.  ￼

7. Build decision memory as first-class graph objects

Your swarm will get much smarter if it remembers decisions separately from facts.

Model these explicitly:
	•	decision
	•	rationale
	•	alternatives rejected
	•	assumptions
	•	superseded_by
	•	depends_on
	•	approved_by
	•	invalidated_at

Why: temporal invalidation is already a natural primitive in this kind of graph, so decisions that expire or get replaced are a perfect fit.  ￼

8. Let agents write uncertainty, not just assertions

A common failure mode is memory corruption by overconfident extraction. Zep’s architecture emphasizes confidence scoring, validation/reflection, provenance, and fact invalidation to reduce hallucinated or stale knowledge.  ￼

So the swarm should write:
	•	claim
	•	confidence
	•	evidence episode ids
	•	source type
	•	valid_from
	•	valid_to
	•	discovered_at
	•	disputed_by
	•	supersedes

That makes the graph a belief system with history, not a bag of frozen claims.

9. Use it for category growth

Since your Ichor IV system wants to grow categories, the graph should power category discovery:
	•	cluster emerging entities and facts
	•	detect repeated uncategorized concepts
	•	surface overcrowded categories
	•	identify bridges between distant clusters
	•	suggest category splits and merges

This is a natural extension of the community-subgraph idea used in Graphiti/Zep, where higher-level topic clusters summarize and organize lower-level graph structure.  ￼

10. Use it as a retrieval contract before every major action

A good swarm rule:

Before an agent is allowed to act, it must answer:
	•	what do we already know?
	•	what changed recently?
	•	what assumptions are stale?
	•	what prior failures are related?
	•	what decisions constrain this move?

That is where the graph beats plain logs. It supports historical and current-state retrieval with provenance and time windows.  ￼

11. Make the graph the source of “memory packets”

Zep exposes a memory context string assembled from relevant graph content for the current session. You should do the same conceptually: build compact, role-specific memory packets for each agent before invocation.  ￼

Examples:
	•	planner packet
	•	coder packet
	•	reviewer packet
	•	researcher packet
	•	coordinator packet

Each packet should contain:
	•	relevant current facts
	•	recent changes
	•	active contradictions
	•	important neighboring entities
	•	applicable constraints
	•	unresolved questions

12. Don’t let every agent query the full graph directly

Introduce memory roles:
	•	writers: ingest episodes and extracted facts
	•	consolidators: deduplicate, invalidate, merge, cluster
	•	retrievers: prepare task-specific context
	•	auditors: inspect contradiction, drift, stale assumptions
	•	governors: enforce memory policy

This is an architectural recommendation, not something directly stated in Zep docs, but it follows from the complexity of temporal graph updates, invalidation, provenance, and retrieval reranking.  ￼

13. Store failures and dead ends aggressively

Most systems only remember successes. The swarm should remember:
	•	failed plans
	•	disproven hypotheses
	•	invalidated assumptions
	•	repeated blockers
	•	untrustworthy sources
	•	broken tool chains

Because the bi-temporal model can preserve what used to be believed and when it became invalid, it is especially suited for retaining “we thought X, then learned Y.”  ￼

14. Best object families to add to your graph

Practical families for swarm use:
	•	agents
	•	teams
	•	missions
	•	objectives
	•	decisions
	•	assumptions
	•	incidents
	•	capabilities
	•	tools
	•	documents
	•	systems
	•	services
	•	categories
	•	entities from user/business domains
	•	episodes
	•	facts
	•	contradictions
	•	communities

Key edges:
	•	worked_on
	•	depends_on
	•	supersedes
	•	contradicts
	•	discovered_in
	•	relevant_to
	•	blocks
	•	resolves
	•	belongs_to_category
	•	collaborates_with
	•	succeeded_by
	•	valid_during

15. The simplest high-value loop

Start with this loop:
	1.	Every task run becomes an episode.
	2.	Every episode extracts entities, facts, decisions, assumptions, and outcomes.
	3.	New facts can invalidate old facts instead of overwriting them.
	4.	Retrieval builds role-specific memory packets from current + historical graph neighborhoods.
	5.	Agents must read packet first, act second, write back third.

That loop is the shortest path from “we have graph memory” to “the swarm actually becomes cumulatively smarter.” It is directly aligned with the temporal, incremental, invalidation-aware memory approach used by Graphiti/Zep.  ￼

Where most swarms fail
	•	they store chat logs, not usable memory
	•	they overwrite instead of invalidate
	•	they store facts without provenance
	•	they retrieve by similarity only
	•	they do not preserve mission continuity
	•	they do not encode decisions and assumptions
	•	they do not remember failures
	•	they do not separate episodic, semantic, and community memory

Your graph already gives you the structure to avoid most of that.  ￼

Bottom line

The swarm should use your bi-temporal graph as:
	•	a continuity layer
	•	a decision ledger
	•	a historical truth system
	•	a role-routing memory
	•	a category-growth engine
	•	a context packet generator

That is where a Zep-like memory system becomes an actual swarm organ instead of an impressive database.

I can turn this into a concrete Elixir-oriented architecture next: graph node/edge types, write pipeline, retrieval pipeline, and swarm-memory roles.
