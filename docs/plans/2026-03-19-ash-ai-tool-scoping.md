# AshAi Tool Scoping Patterns

Research date: 2026-03-19
Source: `deps/ash_ai` (local), `/tmp/travel_agency` (reference repo), ICHOR router + `Ichor.Tools`.

---

## How AshAi Exposes Tools

Tools are declared in the `tools do ... end` DSL block on an **Ash Domain** that carries
the `AshAi` extension:

```elixir
use Ash.Domain, extensions: [AshAi]

tools do
  tool :read_posts, MyApp.Blog.Post, :read
  tool :create_post, MyApp.Blog.Post, :create
end
```

Each `tool` entry is a named alias over `{Resource, Action}`. The name is the stable
atom used everywhere else: in `tools:` lists, in `AshAi.setup_ash_ai/2`, and in
`AshAi.Mcp.Router`.

The struct is `%AshAi.Tool{}` with fields:
`name, resource, action, load, async, domain, identity, description, action_parameters, arguments`.

Key field: `action_parameters` restricts which read-action parameters (sort, filter,
limit, offset, result_type) the LLM can use. Defaults to all five. Pass
`action_parameters: [:filter, :limit]` to narrow.

**Source**: `deps/ash_ai/lib/ash_ai/dsl.ex` (DSL schema), `deps/ash_ai/lib/ash_ai.ex`
(`exposed_tools/1`, `can?/5`).

---

## Router-Level Scoping

`AshAi.Mcp.Router` is a Plug forwarded from Phoenix Router:

```elixir
forward "/mcp", AshAi.Mcp.Router,
  tools: [:tool_a, :tool_b, :tool_c],
  otp_app: :my_app
```

The `tools:` keyword is a **whitelist** of tool names. The server resolves all tools
from all domains registered in `otp_app`'s `:ash_domains` config, then filters to
only those whose `:name` atom is in the list.

**Multiple endpoints = multiple tool profiles.** You can `forward` to separate paths:

```elixir
# Agent endpoint: task + memory tools only
forward "/mcp/agent", AshAi.Mcp.Router,
  tools: [:check_inbox, :get_tasks, :read_memory, :spawn_agent],
  otp_app: :ichor

# Archon endpoint: full fleet management
forward "/mcp/archon", AshAi.Mcp.Router,
  tools: [
    :list_archon_agents, :agent_status, :list_teams,
    :spawn_archon_agent, :stop_archon_agent, :sweep,
    :recent_messages, :archon_send_message, :system_health
  ],
  otp_app: :ichor
```

There is **no built-in profile DSL** in the domain. Profiles are expressed purely by
which tool name atoms appear in each `forward` call.

**Source**: `deps/ash_ai/lib/ash_ai/mcp/router.ex`,
`deps/ash_ai/lib/ash_ai/mcp/server.ex` (`find_tool_by_name/3`, `tools/1`).

### The `actions:` option (alternative to `tools:`)

`setup_ash_ai/2` and `exposed_tools/1` also accept `actions:`:

```elixir
# Restrict by resource+action pairs directly
AshAi.setup_ash_ai(chain,
  otp_app: :ichor,
  actions: [{MyResource, [:action_a, :action_b]}, {OtherResource, :*}]
)
```

When `actions:` is set without `tools:`, the function finds all domain tools whose
`resource` + `action` match. When both `tools:` and `actions:` are set, **both filters
are applied** (intersection). The `actions:` option is not forwarded through
`AshAi.Mcp.Router` -- it is only available in `setup_ash_ai/2`.

---

## Actor-Based Filtering

After name-based filtering, `exposed_tools/1` runs every remaining tool through
`can?/5`:

```elixir
defp can?(actor, domain, resource, action, tenant) do
  if Enum.empty?(Ash.Resource.Info.authorizers(resource)) do
    true
  else
    Ash.can?({resource, action}, actor,
      tenant: tenant,
      domain: domain,
      context: %{private: %{ash_ai_pre_check?: true}},
      maybe_is: true,
      run_queries?: false,
      pre_flight?: false
    )
  end
end
```

This is a **pre-flight policy check**, not a full execution check:
- `maybe_is: true` -- if the policy *might* allow it, include the tool
- `run_queries?: false` -- no DB calls for the check
- `pre_flight?: false` -- allows partial evaluation

**Consequence**: if a resource has an authorizer and the current actor cannot possibly
pass the policy (e.g., `authorize_if actor_attribute_equals(:role, :admin)` but actor
has `role: :user`), the tool is silently removed from the list. The LLM never knows
the tool exists.

This means **authorization policies are the primary actor-scoping mechanism**. To hide
a tool from agent actors but show it to Archon actors, write your policy to deny the
action for agent actors.

### Pattern: Role-Based Tool Visibility via Policies

```elixir
# On the resource:
policies do
  policy action(:sweep) do
    authorize_if expr(^actor(:role) == :archon)
    # agent actors (role: :agent) will fail this => tool hidden from agent MCP list
  end
end
```

The `actor:` passed to `setup_ash_ai/2` or to `AshAi.Mcp.Router` (via
`Ash.PlugHelpers.get_actor/1` from the conn) controls which tools appear.

### How the MCP Server gets the actor

`AshAi.Mcp.Server.handle_post/4` reads actor from the conn:

```elixir
opts = [
  actor: Ash.PlugHelpers.get_actor(conn),
  tenant: Ash.PlugHelpers.get_tenant(conn),
  context: Ash.PlugHelpers.get_context(conn) || %{}
]
|> Keyword.merge(opts)  # router-level opts (tools:, otp_app:) merged on top
```

The Plug pipeline sets the actor before the request reaches the MCP router. Use
`Ash.PlugHelpers.set_actor/2` in a custom plug or authentication plug.

---

## Chat Integration Scoping (`setup_ash_ai/2`)

`AshAi.setup_ash_ai/2` wires tools into a LangChain `LLMChain`:

```elixir
chain
|> AshAi.setup_ash_ai(
  otp_app: :ichor,
  tools: [:check_inbox, :get_tasks, :spawn_agent],
  actor: current_user,
  tenant: tenant,
  context: %{session_id: session_id},
  on_tool_start: fn event -> ... end,
  on_tool_end: fn event -> ... end
)
```

Full option schema from `AshAi.Options`:

| Option | Type | Purpose |
|---|---|---|
| `otp_app` | atom | Auto-discovers tools from all `:ash_domains` registered |
| `tools` | `[atom]` | Whitelist by tool name (applied after `otp_app` discovery) |
| `actions` | `[{Resource, [:action] \| :*}]` | Whitelist by resource+action pairs |
| `exclude_actions` | `[{Resource, :action}]` | Blacklist specific pairs |
| `actor` | any | Passed to all action calls AND used for pre-flight `can?` check |
| `tenant` | Ash.ToTenant | Multitenancy context |
| `context` | map | Forwarded to every action invocation |
| `system_prompt` | `(opts -> string) \| :none` | LLM system message |
| `messages` | `[map]` | Conversation history |
| `on_tool_start` | `(ToolStartEvent) -> any` | Observability hook |
| `on_tool_end` | `(ToolEndEvent) -> any` | Observability hook |

**Tool execution context**: when a tool fires, it uses `context[:actor]` and
`context[:tenant]` from the chain's `custom_context`. This is set by `setup_ash_ai/2`
via `LLMChain.update_custom_context/2`. Actor authorization runs at execution time too
-- the pre-flight check only hides tools from the list; actual execution is still
authorized by full Ash policies.

### Scoping by actor type at chat time

The travel_agency pattern: pass the `actor` explicitly and let policies do the rest.

```elixir
# Archon chat session: full tool set
chain
|> AshAi.setup_ash_ai(
  otp_app: :ichor,
  actor: %Ichor.Archon{},  # or however Archon actor is represented
  tools: @archon_tools
)

# Agent chat session: restricted tool set
chain
|> AshAi.setup_ash_ai(
  otp_app: :ichor,
  actor: current_agent,
  tools: @agent_tools
)
```

Define `@archon_tools` and `@agent_tools` as module attributes or functions that
return the appropriate atom lists.

---

## Travel Agency Patterns

The travel_agency repo uses a minimal, focused approach:

1. **Single domain with AshAi extension** (`TravelAgency.Integrations`) declares one
   tool: `:book_trip`. No profiles, no role-based scoping, no multiple endpoints.

2. **Explicit tool list in chat change module**:
   ```elixir
   |> AshAi.setup_ash_ai(otp_app: :travel_agency, tools: [:book_trip], actor: context.actor)
   ```
   The tool list is hardcoded in the change module -- not derived from the actor. This
   is appropriate when a single chat endpoint always gets the same tool set.

3. **No MCP router configured** -- the travel_agency does not use `AshAi.Mcp.Router`.
   Tools are only accessible through the `LLMChain` chat path.

4. **Actions resource pattern**: tools live on an `Actions` resource that groups
   related custom actions (`book_trip`, `compose_confirmation_email`). This resource
   has no persistent data -- it exists only as a namespace for Ash actions that agents
   can call. One tool bridges into a Reactor (`TripReactor`), another uses a
   `prompt(...)` backed action directly.

5. **`%AshAi{}` struct as actor for internal writes**: streaming assistant messages are
   written using `actor: %AshAi{}`. The resource bypasses normal policy checks for
   the upsert action using `bypass action(:upsert_response) { authorize_if AshAi.Checks.ActorIsAshAi }`.

---

## Recommended Patterns for ICHOR

### Current state

ICHOR already has a solid base:
- `Ichor.Tools` domain with AshAi extension: 62 tools declared
- Single `/mcp` endpoint with a 39-tool agent whitelist
- No `/mcp/archon` endpoint (Archon tools defined but not exposed)

### Pattern 1: Split into two MCP endpoints

The current `/mcp` route exposes only agent tools. Archon tools (`:list_archon_agents`,
`:sweep`, `:system_health`, etc.) are declared but not wired to any endpoint.

```elixir
# router.ex

# Agent endpoint: 39 task/memory/genesis/dag tools
forward "/mcp", AshAi.Mcp.Router,
  tools: @agent_tool_names,
  otp_app: :ichor

# Archon endpoint: ~20 fleet management tools
forward "/mcp/archon", AshAi.Mcp.Router,
  tools: @archon_tool_names,
  otp_app: :ichor
```

Define `@agent_tool_names` and `@archon_tool_names` as module attributes in the router
for clarity. This requires the Archon MCP endpoint to use a different authentication
plug.

### Pattern 2: Tool profile module attributes (no new abstractions)

Extract tool name lists into a dedicated module rather than inline in the router:

```elixir
defmodule Ichor.Tools.Profiles do
  @moduledoc "Named tool profiles for each MCP endpoint."

  @agent_tools [
    :check_inbox, :acknowledge_message, :send_message,
    :get_tasks, :update_task_status,
    :read_memory, :memory_replace, :memory_insert, :memory_rethink,
    :conversation_search, :conversation_search_date,
    :archival_memory_insert, :archival_memory_search,
    :spawn_agent, :stop_agent, :create_agent, :list_agents,
    :create_genesis_node, :advance_node, :list_genesis_nodes,
    :get_genesis_node, :gate_check,
    :create_adr, :update_adr, :list_adrs,
    :create_feature, :list_features,
    :create_use_case, :list_use_cases,
    :create_checkpoint, :create_conversation, :list_conversations,
    :create_phase, :create_section, :create_task, :create_subtask, :list_phases,
    :next_jobs, :claim_job, :complete_job, :fail_job,
    :get_run_status, :load_jsonl, :export_jsonl
  ]

  @archon_tools [
    :list_archon_agents, :agent_status, :list_teams,
    :spawn_archon_agent, :stop_archon_agent, :pause_agent, :resume_agent, :sweep,
    :recent_messages, :archon_send_message,
    :system_health, :tmux_sessions,
    :manager_snapshot, :attention_queue,
    :agent_events, :fleet_tasks,
    :search_memory, :remember, :query_memory,
    :list_projects, :create_project, :check_operator_inbox, :mes_status, :cleanup_mes
  ]

  def agent, do: @agent_tools
  def archon, do: @archon_tools
end
```

Then in the router:

```elixir
alias Ichor.Tools.Profiles

forward "/mcp", AshAi.Mcp.Router,
  tools: Profiles.agent(),
  otp_app: :ichor

forward "/mcp/archon", AshAi.Mcp.Router,
  tools: Profiles.archon(),
  otp_app: :ichor
```

### Pattern 3: Actor-based filtering for the Archon chat path

When `Ichor.Archon.Chat.TurnRunner` builds its `LLMChain`, pass the Archon actor
and the archon tool profile:

```elixir
chain
|> AshAi.setup_ash_ai(
  otp_app: :ichor,
  tools: Ichor.Tools.Profiles.archon(),
  actor: %Ichor.Archon{},
  context: %{session_id: session_id}
)
```

For agent sessions routed through the gateway:

```elixir
chain
|> AshAi.setup_ash_ai(
  otp_app: :ichor,
  tools: Ichor.Tools.Profiles.agent(),
  actor: current_agent,
  context: %{session_id: agent.session_id, agent_id: agent.id}
)
```

### Pattern 4: Policy-based tool hiding (for fine-grained actor scoping)

If specific tools must be invisible to certain actor types beyond what a list split can
express, add a policy to the tool resource:

```elixir
# In the resource action's resource:
policies do
  policy action(:sweep) do
    authorize_if expr(^actor(:type) == :archon)
  end
end
```

The pre-flight `can?` check in `exposed_tools/1` will silently drop the tool from the
list for agent actors even if it appears in the whitelist.

### Pattern 5: `exclude_actions` for one-off suppressions

If a tool is in the domain but should never be exposed to a particular endpoint:

```elixir
forward "/mcp", AshAi.Mcp.Router,
  tools: Profiles.agent(),
  exclude_actions: [{Ichor.AgentTools.Spawn, :stop_agent}],
  otp_app: :ichor
```

Note: `exclude_actions` takes `{Resource, :action_name}` pairs (action name, not tool
name).

---

## Key Constraints and Gotchas

1. **Tool names must be unique across the domain.** The router finds tools by name
   atom. If two tools in `Ichor.Tools` have the same name atom, the first one wins.

2. **`otp_app` vs `actions:`** -- when `otp_app` is used, AshAi reads
   `Application.get_env(:ichor, :ash_domains)` to find all domains. If `Ichor.Tools`
   is not in that list, no tools are discovered. The `validate_config_inclusion?: false`
   in `Ichor.Tools` suppresses the warning about this.

3. **Pre-flight check uses empty input.** Policies on create/update/destroy actions
   that reference changeset attributes (not actor attributes) may raise errors during
   the pre-flight check. Add `only_when_valid?: true` to those changes, or check
   `changeset.valid?` inside the change.

4. **Async tools** default to `async: true`. All tools in a single LLMChain run will
   be dispatched concurrently. Set `async: false` on tools that have ordering
   dependencies.

5. **`load:` option for private data.** Private attributes are excluded from tool
   responses by default. Use `load: [:private_field]` in the tool DSL to include them.
   Private attributes cannot be used for filtering/sorting regardless of `load:`.

6. **`action_parameters:` restricts read action query capabilities.** If you want to
   prevent an LLM from using arbitrary filters on a read action, pass
   `action_parameters: [:limit]` to expose only pagination, not filtering.
