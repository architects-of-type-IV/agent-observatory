# Ichor Target Ash Model

This is the concrete target model implied by the clarified product truths.

It is not an implementation diff.
It is the intended Ash surface:

- real resources
- real relationships
- real actions
- explicit non-resources

## Stable Concepts

These now look durable:

- `Project`
- planning artifacts attached to a project
- `Task`
- `Run`
- `Job`
- `AgentType`
- `Team`
- `TeamMember`
- signals as reactive transport

These do not currently look like durable business concepts:

- `fleet`
- `blueprint`
- `node`
- `genesis` as a separate persisted noun
- `tasks.jsonl`

## Domain Split

Use four domains.

### Team/Agent Domain

Owns:

- `AgentType`
- `Team`
- `TeamMember`
- live/discovered agents
- team spawning
- operator interventions

### Project/Execution Domain

Owns:

- `Project`
- planning artifacts
- `Task`
- derived DAG execution
- `Run`
- `Job`

### Observatory Domain

Owns:

- durable/queryable events
- sessions
- messages
- errors
- intervention audit history

### Signals Domain

Owns:

- signal catalog
- signal emission
- signal buffering
- pub/sub transport

## Team Model

This is the clearest part of the target model.

### `AgentType`

Reusable default behavior authored in Workshop.

Suggested attributes:

- `name`
- `capability`
- `default_model`
- `default_permission`
- `default_persona`
- `default_file_scope`
- `default_quality_gates`
- `default_tools`
- `color`
- `sort_order`

Suggested actions:

- `create`
- `update`
- `destroy`
- `sorted`

Notes:

- `default_tools` should be explicit, not inferred from global tool profiles.
- This is where reusable prompt defaults live.

### `Team`

Durable authored team definition.

Suggested attributes:

- `name`
- `strategy`
- `cwd`
- `spawn_profile`
- `notes`

Suggested relationships:

- `has_many :members`

Suggested aggregates/calculations:

- `count :member_count`
- `calculate :tool_names`

Suggested actions:

- `create`
- `update`
- `destroy`
- `by_name`
- `list_all`
- `spawn_team`

Important:

- `spawn_team` belongs here.
- The frontend "Launch Team" button should ultimately call `spawn_team(team_name)`.

### `TeamMember`

This now looks like a real resource, not just an embedded shape.

Reason:

- belongs to a team
- points at an agent type
- has team-specific instructions
- has communication metadata
- likely has tool-scope overrides
- is independently edited in Workshop

Suggested attributes:

- `name`
- `position`
- `model_override`
- `permission_override`
- `extra_instructions`
- `file_scope_override`
- `quality_gates_override`
- `tool_scope_override`
- `canvas_x`
- `canvas_y`

Suggested relationships:

- `belongs_to :team`
- `belongs_to :agent_type`
- `many_to_many :communicates_with, TeamMember`

Alternative to `many_to_many`:

- keep communication rules as a child resource if routing/policy becomes complex

Suggested calculations:

- `effective_model`
- `effective_permission`
- `effective_persona`
- `effective_file_scope`
- `effective_quality_gates`
- `effective_tools`
- `effective_prompt_input`

Suggested actions:

- `create`
- `update`
- `destroy`
- `for_team`
- `reposition`

### Communication Rules

Do not decide too early.

Two acceptable shapes:

1. Embedded/JSON child data on `Team`
2. Real `TeamCommunicationRule` resource

Choose `TeamCommunicationRule` only if it is independently queried, validated, or edited enough to justify its own persistence identity.

For now the likely target is:

- real `TeamMember`
- embedded communication rules on `Team`

unless route/via semantics become first-class.

## `spawn_team/1`

This should be the public API shape.

Suggested code interface:

```elixir
code_interface do
  define :spawn_team, args: [:name]
end
```

Suggested action shape:

```elixir
action :spawn_team, :map do
  argument :name, :string, allow_nil?: false
end
```

Conceptual implementation:

1. load team by name
2. load ordered members with agent types
3. compute effective member config from agent type defaults + member overrides
4. build communication context for every member
5. build prompt input for every member
6. inject:
   - teammate identities
   - MCP communication instructions
   - tmux/session identity
   - allowed tools
7. launch the runtime team
8. return team/session summary

Suggested return shape:

- `team_name`
- `session`
- `member_count`
- `members`
- `status`

Important:

- `spawn_team("mes")`
- `spawn_team("mode-a")`
- `spawn_team("mode-b")`
- `spawn_team("mode-c")`

should all be the same action shape over different team definitions.

## Project Model

The project is the real persisted concept on `/mes`.

`node` / `genesis` should not survive as a separate persisted resource unless the lifecycle proves it must.

### `Project`

Suggested attributes:

- `title`
- `description`
- `subsystem`
- `signal_interface`
- `topic`
- `version`
- `architecture`
- `dependencies`
- `signals_emitted`
- `signals_subscribed`
- `status`
- `cwd`
- `build_log`

Suggested relationships:

- `has_many :artifacts`
- `has_many :tasks`
- `has_many :runs`

Suggested calculations:

- `planning_stage`
- `gate_readiness`

Suggested actions:

- `create`
- `update`
- `pick_up`
- `mark_compiled`
- `mark_loaded`
- `mark_failed`
- `list_all`
- `spawn_team`
- `generate_tasks`

Notes:

- `spawn_team` here can be a convenience wrapper only if you want project-driven spawning.
- The canonical launch primitive should still be team-domain `spawn_team(name)`.

## Planning Artifacts

Do not keep `Artifact` as one resource unless you can defend the unified shape.

The safer target is to split the planning concepts that have clearly different rules.

Likely real resources:

- `Decision` for ADR-like records
- `UseCase`
- possibly `Feature`
- possibly `Checkpoint`
- possibly `Conversation`

Minimum split rule:

- if it has different lifecycle, validation, relationships, or UI behavior, it should not be hidden behind one `kind`

If you want to keep file count down, the compromise is:

- split only the clearly distinct concepts first
- keep the more document-like artifacts unified only if they truly share behavior

## Task Model

This is now clear.

Tasks are created from MES project specs/planning output.
The DAG is derived from tasks.
`tasks.jsonl` is a sync boundary, not the core model.

### `Task`

Suggested attributes:

- `external_id`
- `subject`
- `description`
- `goal`
- `allowed_files`
- `steps`
- `done_when`
- `blocked_by`
- `priority`
- `wave`
- `acceptance_criteria`
- `phase_label`
- `tags`
- `notes`
- `status`
- `owner`
- `cwd`

Suggested relationships:

- `belongs_to :project`

Suggested actions:

- `create`
- `update`
- `claim`
- `complete`
- `fail`
- `reset`
- `reassign`
- `for_project`
- `available`
- `sync_to_jsonl`
- `sync_from_jsonl`

Important:

- `Task` is the domain truth
- `wave` is derived or maintained as part of DAG derivation
- `blocked_by` expresses DAG dependencies

If needed, add:

- `derive_dag`

as a domain action/read, not as a resource.

## Execution Model

The current `Run` and `Job` concepts still look valid.

### `Run`

Represents an execution session over a set of tasks.

Suggested relationships:

- `belongs_to :project`
- `has_many :jobs`

Suggested actions:

- `create`
- `complete`
- `fail`
- `archive`
- `active`

### `Job`

Execution unit inside a run.

This may stay distinct from `Task` if:

- tasks are the durable plan
- jobs are run-specific execution instances/snapshots

That split makes sense in many systems.

Suggested relationships:

- `belongs_to :run`
- `belongs_to :task`

Suggested actions:

- `create`
- `claim`
- `complete`
- `fail`
- `reset`
- `reassign`
- `available`

## `tasks.jsonl` Boundary

This should not be modeled as its own business entity.

It is an integration/sync surface for multi-repo workflows.

Keep this as:

- sync action(s)
- runtime/import-export helper

Not as:

- source-of-truth resource
- separate planning domain

## Signals Model

Signals remain their own domain.

Keep:

- catalog
- emit/read actions if useful
- buffer
- runtime

Use signals for:

- reactivity
- cross-team coordination
- Archon subscriptions

Do not force signals to become the persistent business model.

## What Should Probably Be Deleted Or Collapsed

Once the target model exists, these current structures should mostly disappear:

- synthetic `tools/` resources
- `BlueprintState`
- preparation modules used to fake read models
- `node` as separate persisted concept, unless proven necessary
- `spawn` god modules

## Minimal Target API

If the refactor had to preserve only one clean public surface, it should be this:

### Team/Agent

- `create_team`
- `update_team`
- `spawn_team`
- `create_agent_type`
- `update_agent_type`
- `list_live_agents`

### Project/Planning

- `create_project`
- `update_project`
- `create_decision`
- `create_use_case`
- `generate_tasks`

### Task/Execution

- `list_tasks`
- `claim_task`
- `complete_task`
- `fail_task`
- `start_run`
- `run_status`

### Signals

- `emit_signal`
- `recent_signals`
- `signal_catalog`

That is a much more coherent system than the current synthetic tool-wrapper surface.

