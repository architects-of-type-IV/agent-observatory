# ICHOR IV - Handoff

## Current Status: MES Researcher Prompt Redesign COMPLETE (2026-03-14)

### What Was Done This Session
**Redesigned MES researcher prompts** in `lib/ichor/mes/team_spawner.ex`:

Replaced single `researcher_prompt/3` with two specialized functions:
- `researcher_1_prompt/2` (DRIVER) -- generates 3 proposals across different domains, sends to researcher-2 for critique, iterates based on feedback, delivers final to coordinator
- `researcher_2_prompt/2` (CRITIC) -- reviews proposals, does web research to strengthen best one, sends structured PICK/DEAD/STRENGTHEN/AVOID feedback, approves final revision

Both prompts include: full Ichor app context, dead zones (banned topics: signal correlation, anomaly detection, entropy, self-healer, load balancing), fresh territory suggestions, and Subsystem behaviour contract.

Also updated:
- **Coordinator Phase 1**: collaboration-framed start signals instead of hardcoded topic assignments
- **Coordinator Phase 2**: waits for ONE message from researcher-1 only
- **Planner prompt**: expects single developed proposal, max 2 turns

### Message Flow
```
Coordinator --START--> R1 --[3 proposals]--> R2
R2 --[PICK/STRENGTHEN/AVOID]--> R1
R1 --[revised]--> R2 --[READY]--> R1
R1 --[final]--> Coordinator --> Planner --> Lead --> Operator
```

### Build Status
- `mix compile --warnings-as-errors` -- CLEAN

### Next Step
- Test with a live MES run to verify the collaboration loop
