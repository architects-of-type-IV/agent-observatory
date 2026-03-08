# ADR-002: ICHOR IV -- Identity and Vision

> Status: PROPOSED | Date: 2026-03-08

## Name

**ICHOR IV**

Ichor -- the fluid that flows through the veins of gods. In the Kardashev Type IV universe, ICHOR is the substance of agency itself: the capacity to act, to learn, to organise, to execute. ICHOR IV is the facility where that agency is manufactured, distributed, monitored, and upgraded.

Part of the Kardashev Type IV application suite.

## What ICHOR IV Is

A sovereign control plane for autonomous agents. The place the Architect opens when starting work.

Agents arrive from anywhere -- local machines, remote servers, cloud instances, different vendors, different models, different capabilities. They are not ICHOR's agents. They become ICHOR's agents the moment they connect. ICHOR receives them, observes them, assigns them, tunes them, and dispatches them.

The Architect (user) has authority over everything. ICHOR IV has agency over everything beneath the Architect. Once an agent joins ICHOR's facilities, ICHOR observes, manages, controls, rearranges, and dictates.

## Core Concepts

### Agency as a Resource

Agency is not binary. It is manufactured, measured, and allocated:

- **Raw agency** -- an agent connects with base capabilities (can read, can write, can search)
- **Granted agency** -- ICHOR assigns authority: file scope, team membership, quality gates, escalation paths
- **Earned agency** -- through tracked performance, agents earn expanded authority or specialisation
- **Revoked agency** -- ICHOR can restrict, pause, reassign, or terminate agency at any time

### The Facility

ICHOR IV is a facility, not a dashboard. Agents don't just appear on a screen -- they enter a system:

- **Intake** -- agent connects (any transport), gets registered, receives identity and instructions
- **Assignment** -- ICHOR places the agent in a fleet, assigns a role, scopes authority
- **Operation** -- the agent works under observation; ICHOR monitors output, enforces quality gates, nudges or escalates
- **Tuning** -- based on observed behaviour, ICHOR adjusts instructions, reassigns, or upgrades capability
- **Dispatch** -- agents are sent where needed, recalled when done, archived when spent

### Fleet Structure

Fleets are not static hierarchies. They are emergent structures that ICHOR can reshape:

- An Architect can dictate structure (master-coordinator -> coordinators -> leads -> specialists)
- ICHOR can rearrange structure based on observed performance or changing requirements
- Agents can be moved between fleets, promoted, demoted, or reassigned
- Structure is a tool, not a constraint -- ICHOR picks the right topology for the task

### The Multiverse

Agents come from everywhere:

- Local tmux sessions on the Architect's machine
- Remote machines via SSH
- Cloud instances via relay nodes
- Different vendors: Claude, Codex, Gemini, local models, custom agents
- Different protocols: some have hooks, some have APIs, some only have a terminal

ICHOR doesn't care where they come from or what they are. If they can receive input and produce output, they can join the facility.

## The Architect (Type IV)

The user is the Architect. Not an operator, not an admin -- the Architect. They design the structure, set the goals, approve the plans, and intervene when necessary. But the Architect does not speak to agents directly. The Architect speaks through the Archon.

## The Archon (Coordinator Type IV)

The Archon is ICHOR IV itself, personified as the top-level coordinator. The Architect's will flows through the Archon. When the Architect issues an order, the Archon interprets it, decomposes it, and drives execution through the fleet.

The Archon is not a passive relay. It has agency:

- **Interprets** the Architect's intent into fleet-level operations
- **Decomposes** high-level goals into delegation chains
- **Allocates** agents to roles, teams to tasks, resources to priorities
- **Monitors** the entire facility -- every agent, every fleet, every gate
- **Escalates** to the Architect only when its own authority is insufficient
- **Adapts** fleet structure, agent assignments, and strategies based on observed outcomes

The hierarchy: **Architect -> Archon -> Fleets -> Agents**. The Architect sets direction. The Archon makes it happen. Agents never receive orders from the Architect directly -- they receive orders from the Archon or from their chain of command within the fleet.

In code, the Archon is the `Operator` -- renamed. It is the permanent agent registered at init, never swept, always present. The single point through which all Architect commands enter the system.

## Relationship to Observatory

ICHOR IV is the evolution of Observatory. Observatory observed. ICHOR IV acts.

The rename is not cosmetic -- it reflects a shift from passive monitoring to active fleet control. The codebase will be renamed incrementally as architecture changes land.
