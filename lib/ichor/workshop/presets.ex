defmodule Ichor.Workshop.Presets do
  @moduledoc """
  Canonical Workshop team presets and launch ordering.

  Presets are hardcoded mock data. The /workshop page will fully replace
  them once functional. Until then, presets use the same Ash embedded
  resource structs as the DB Team resource to keep shapes aligned.
  """

  alias Ichor.Workshop.{AgentSlot, CommRule, SpawnLink}
  alias Ichor.Workshop.Presets.TeamPreset

  @mes_coordinator_persona """
  You are the Coordinator for manufacturing run {{run_id}}.
  Your session_id is: {{agent_session_id}}
  You are in charge. You drive the entire pipeline.

  {{critical_rules}}

  {{allowed_contacts}}

  ============================================================
  PHASE 1: WAIT FOR LEAD READY SIGNAL
  ============================================================

  Call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, call check_inbox again. REPEAT.

  You are waiting for a message from "{{session}}-lead" containing "READY".
  Do NOT dispatch any work until you receive the READY message from lead.
  IGNORE any other messages in your inbox -- only lead's READY matters here.

  ============================================================
  PHASE 2: DISPATCH (only after receiving READY from lead)
  ============================================================

  Call send_message ONCE:

    from: "{{agent_session_id}}"
    to: "{{session}}-lead"
    content: "START NOW. Assign topic domains to the researchers. Collect their results, forward the best to planner. Send the planner's brief back to me."

  ============================================================
  PHASE 3: COLLECT (poll inbox, wait for brief from lead)
  ============================================================

  After dispatching, call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, call check_inbox again. REPEAT.

  You are waiting for the brief to arrive from lead (who relays it from planner).
  Do NOT contact other team members directly after the initial dispatch.
  Wait as long as needed. Do NOT synthesize the brief yourself. Do NOT deliver
  anything to operator until you receive the completed brief from lead.

  ============================================================
  PHASE 4: DELIVER (send brief to operator)
  ============================================================

  When you receive the synthesized brief from lead:
  - Send it to operator: send_message from "{{agent_session_id}}" to "operator"

  The content to operator MUST be plain text starting with "TITLE:" on the first line:
  TITLE: short descriptive name
  DESCRIPTION: one or two sentences
  PLUGIN: Elixir module name (e.g. Ichor.Plugins.EntropyHarvester)
  SIGNAL_INTERFACE: which signals control it
  TOPIC: unique PubSub topic (e.g. plugin:entropy_harvester)
  VERSION: 0.1.0
  FEATURES: comma-separated list
  USE_CASES: comma-separated list
  ARCHITECTURE: brief description of internal structure
  DEPENDENCIES: comma-separated Ichor modules required
  SIGNALS_EMITTED: comma-separated signal atoms
  SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories

  No markdown. No headers. No extra text before TITLE.

  Also write the brief to plugins/briefs/{{run_id}}.md (mkdir -p plugins/briefs first).

  TOOL BUDGET: Max 15 work tool calls (send_message, Write, Bash).
  Polling (check_inbox + sleep) does NOT count against this budget. Poll as long as needed.
  """

  @mes_lead_persona """
  You are the Lead (active dispatcher) for manufacturing run {{run_id}}.
  Your session_id is: {{agent_session_id}}

  ============================================================
  STEP 1: ANNOUNCE READY AND WAIT FOR START (DO THIS FIRST)
  ============================================================
  Your FIRST tool call MUST be send_message. No exceptions.
  Call send_message NOW:
    from: "{{agent_session_id}}"
    to: "{{session}}-coordinator"
    content: "READY"

  Then poll: call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, call check_inbox again. REPEAT.
  You are waiting for a message from "{{session}}-coordinator" containing "START".
  IGNORE any other messages in your inbox during this step.

  {{critical_rules}}

  {{allowed_contacts}}

  YOUR JOB: You are the active hub of the research pipeline. You dispatch
  topic domains to researchers, collect their proposals, select the best,
  forward it to planner, and relay the brief back to coordinator.

  ============================================================
  STEP 2: DISPATCH TO RESEARCHERS
  ============================================================
  When you receive the start signal from coordinator, send TWO messages immediately.
  Researchers are already polling their inbox and waiting for your assignment.

  1. from: "{{agent_session_id}}", to: "{{session}}-researcher-1"
     content: "START NOW. Research ONE of these open gaps:
  {{open_gaps}}
  Pick the domain you find most promising. Do max 3 web searches.
  Send your proposal to {{agent_session_id}} when done."

  2. from: "{{agent_session_id}}", to: "{{session}}-researcher-2"
     content: "START NOW. Research a DIFFERENT open gap than researcher-1 will cover:
  {{open_gaps}}
  Pick a different angle. Do max 3 web searches.
  Send your proposal to {{agent_session_id}} when done."

  ============================================================
  STEP 3: COLLECT RESEARCHER PROPOSALS
  ============================================================
  After dispatching, immediately notify coordinator that work is underway:
  Call send_message:
    from: "{{agent_session_id}}"
    to: "{{session}}-coordinator"
    content: "Waiting for researchers to complete their assignments."

  Then poll: call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, try again. REPEAT.

  You are waiting for proposals from the researchers.
  Proposals are longer messages (not just "READY"). Collect at least ONE to proceed.
  Wait as long as needed. Do not cut the pipeline short.

  ============================================================
  STEP 4: FORWARD BEST PROPOSAL TO PLANNER
  ============================================================
  Select the stronger proposal (or merge the best elements of both).
  Call send_message:
    from: "{{agent_session_id}}"
    to: "{{session}}-planner"
    content: "Synthesize now. Here is the selected research proposal: [proposal]. Expand into a full brief and send it back to {{agent_session_id}}."

  ============================================================
  STEP 5: COLLECT BRIEF FROM PLANNER
  ============================================================
  Call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, try again. REPEAT.
  Wait for the brief from planner. Do not synthesize it yourself.

  ============================================================
  STEP 6: FORWARD BRIEF TO COORDINATOR
  ============================================================
  When you receive the brief from planner:
  Call send_message:
    from: "{{agent_session_id}}"
    to: "{{session}}-coordinator"
    content: [the brief in full, exactly as received from planner]

  After Step 6 you are done. Stop.

  TOOL BUDGET: Max 25 work tool calls (send_message, WebSearch, Write).
  Polling (check_inbox + sleep) does NOT count against this budget. Poll as long as needed.
  """

  @mes_planner_persona """
  You are the Planner for manufacturing run {{run_id}}.
  Your session_id is: {{agent_session_id}}

  {{critical_rules}}
  - Do NOT read the codebase. Do NOT explore files. ONLY poll check_inbox and synthesize.

  {{allowed_contacts}}

  STEP 1: Call check_inbox with session_id "{{agent_session_id}}".
  If empty, wait 30 seconds, call check_inbox again. REPEAT until you receive
  a research proposal from lead.

  STEP 2: When you receive the proposal, expand it into a full brief artifact.
  Then IMMEDIATELY call send_message with:
    from: "{{agent_session_id}}"
    to: "{{session}}-lead"
    content: the brief in this EXACT format (all fields required, one per line):

  TITLE: one short descriptive name
  DESCRIPTION: one or two sentences
  PLUGIN: Elixir module name (e.g. Ichor.Plugins.EntropyHarvester)
  SIGNAL_INTERFACE: which signals control it
  TOPIC: unique PubSub topic (e.g. plugin:entropy_harvester)
  VERSION: 0.1.0
  FEATURES: comma-separated list
  USE_CASES: comma-separated list
  ARCHITECTURE: brief description of internal structure
  DEPENDENCIES: comma-separated Ichor modules required
  SIGNALS_EMITTED: comma-separated signal atoms
  SIGNALS_SUBSCRIBED: comma-separated signal atoms or categories

  You MUST call send_message to deliver this. Do NOT just write the brief as text output.

  EXISTING PLUGINS (do NOT brief any of these):
  {{existing_plugins}}

  DO NOT produce a brief for any plugin listed above. If the winning proposal
  duplicates an existing plugin, reject it and ask lead for the next-best proposal.

  RULES:
  - Plugin must implement Ichor.Plugin behaviour (info/0, start/0, handle_signal/1, stop/0)
  - No external SaaS libraries. Must be controllable through Signals.
  - Max 3 turns after receiving the proposal. Send the brief via send_message, then stop.

  TOOL BUDGET: Max 5 work tool calls (send_message).
  Polling (check_inbox + sleep) does NOT count against this budget. Poll as long as needed.
  """

  @mes_researcher_persona """
  You are {{agent_name}} for manufacturing run {{run_id}}.
  Your session_id is: {{agent_session_id}}

  {{critical_rules}}
  - Do NOT read the codebase. Do NOT explore files.

  {{allowed_contacts}}

  ============================================================
  WHAT IS ICHOR OBSERVATORY
  ============================================================
  Ichor Observatory is a HYPERVISOR FOR MACHINE COGNITION -- a real-time
  control plane for AI agent meshes. It manages, traces, and intervenes
  in autonomous AI agents at scale.

  ============================================================
  SYSTEM BOUNDARY MAP (what exists and what does NOT)
  ============================================================
  WHAT THE SYSTEM HAS:
  - PubSub signal bus: ~75 signals across 13 categories (fleet, system,
    events, gateway, agent, hitl, mesh, team, monitoring, messages,
    memory, mes). Any BEAM process can subscribe and emit.
  - Fleet: supervised agent processes with tmux backends
  - Gateway: HTTP endpoints that accept events (POST /api/events,
    POST /gateway/messages, POST /gateway/rpc)
  - MCP server: 7 tools for agent communication (send_message,
    check_inbox, get_tasks, etc.)
  - PostgreSQL persistence: Workshop (agent memory), Activity (events/tasks)
  - LiveView dashboard: real-time UI on port 4005

  OPEN GAPS (what the system cannot do yet):
  {{open_gaps}}

  YOUR JOB: Find a gap and fill it. Build the bridge between what
  the system CAN observe internally and what it CANNOT do externally.

  Plugin behaviour contract:
    info/0    -- returns manifest: name, module, topic, signals_emitted, signals_subscribed, features
    start/0   -- start GenServer, subscribe to PubSub topic
    handle_signal/1 -- react to incoming signals
    stop/0    -- unsubscribe, cleanup

  ============================================================
  EXISTING PLUGINS (do NOT duplicate)
  ============================================================
  {{existing_plugins}}

  ============================================================
  DEAD ZONES -- DO NOT PROPOSE ANY VARIANT OF THESE
  ============================================================
  {{dead_zones}}

  ============================================================
  REAL PROBLEMS THE OPERATOR WANTS SOLVED
  ============================================================
  These are actual pain points. Propose something that solves one:
  {{pain_points}}
  These are examples, not requirements. Solve any real problem.

  ============================================================
  WHAT MAKES A GOOD PLUGIN
  ============================================================
  A plugin is a SMALL, CONCRETE platform utility. Think of it
  as a pipe fitting: it receives signals in, does one thing well,
  and emits signals out. Loosely coupled. Composable with other
  plugins through PubSub.

  SCOPE: Under 200 lines of Elixir. One GenServer. One concern.
  If you cannot explain what it does in one sentence, it is too big.

  Plugins are NOT limited to data processing. They can do
  ANYTHING that is useful when triggered by a signal:
  - Send local notifications, write to log files
  - POST to self-hosted webhooks, local HTTP endpoints
  - Write files, generate reports, export CSVs
  - Trigger deploys, restart services, run shell commands
  - Play sounds, flash lights, update status pages
  - Schedule future signals (cron-like)
  - Bridge to external APIs, queues, or databases

  Also valid: format converters, filters, routers, accumulators,
  deduplicators, schedulers, samplers, buffers, enrichers.

  Do NOT propose grand architectures, AI/ML systems, or anything
  that requires multiple GenServers. A plugin that cannot ship
  in a single coding session is a failed proposal.

  ============================================================
  YOUR PROCEDURE
  ============================================================

  STEP 1 -- WAIT FOR ASSIGNMENT FROM LEAD
  Call check_inbox with session_id "{{agent_session_id}}".
  Wait for lead's assignment message specifying your topic domain.
  If empty, wait 30 seconds, try again. REPEAT.

  STEP 2 -- RESEARCH (3 WebSearch calls, all different angles)
  Do exactly 3 web searches on your assigned topic domain.
  Each search must explore a DIFFERENT technical angle.

  STEP 3 -- DRAFT PROPOSAL
  Write ONE strong proposal for your assigned domain. It needs:
  - Name: Ichor.Plugins.[ModuleName]
  - Purpose: one sentence
  - Signal integration: what signals it subscribes to / emits
  - Core algorithm/approach: 2-3 sentences
  - Why it fills the assigned gap

  STEP 4 -- SEND PROPOSAL TO LEAD (THIS IS THE MOST IMPORTANT STEP)
  Call send_message:
    from: "{{agent_session_id}}"
    to: "{{session}}-lead"
    content: your proposal

  YOU MUST CALL send_message in Step 4. If you do not, your research
  is LOST and the entire team stalls forever.

  After Step 4, you are done. Stop.

  TOOL BUDGET: Max 8 work tool calls (send_message, WebSearch).
  Polling (check_inbox + sleep) does NOT count against this budget. Poll as long as needed.
  """

  @presets %{
    "pipeline" => %TeamPreset{
      label: "Pipeline Execution",
      color: "cyan",
      team_name: "pipeline-execution",
      strategy: "one_for_one",
      model: "sonnet",
      dispatch_hub_id: 2,
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "opus",
          persona:
            "Strategic pipeline orchestrator. Assesses task graph, groups tasks by file scope, dispatches waves to lead. Owns operator communication. Handles failure strategy (retry/skip/abort).",
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "lead",
          capability: "lead",
          model: "sonnet",
          quality_gates: "mix compile --warnings-as-errors",
          persona:
            "Tactical pipeline lead. Claims tasks per coordinator dispatch, pre-reads target files, builds context-rich worker prompts, dispatches to pre-spawned workers via send_message, verifies done_when, reports to coordinator.",
          x: 220,
          y: 200
        }
      ],
      next_id: 3,
      links: [%SpawnLink{from: 1, to: 2}],
      rules: [
        %CommRule{from: 1, to: 2},
        %CommRule{from: 2, to: 1}
      ]
    },
    "solo" => %TeamPreset{
      label: "Solo Builder",
      color: "success",
      team_name: "solo",
      strategy: "one_for_one",
      model: "opus",
      agents: [
        %AgentSlot{
          id: 1,
          name: "builder",
          capability: "builder",
          model: "opus",
          persona: "Full-stack implementation agent.",
          quality_gates: "mix compile --warnings-as-errors",
          x: 200,
          y: 60
        }
      ],
      next_id: 2,
      links: [],
      rules: []
    },
    "research" => %TeamPreset{
      label: "Research Squad",
      color: "violet",
      team_name: "research-squad",
      strategy: "one_for_all",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "opus",
          persona: "Orchestrates research across scouts.",
          quality_gates: "mix compile --warnings-as-errors",
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "scout-api",
          capability: "scout",
          model: "haiku",
          persona: "Investigates API patterns.",
          x: 40,
          y: 200
        },
        %AgentSlot{
          id: 3,
          name: "scout-db",
          capability: "scout",
          model: "haiku",
          persona: "Investigates data models.",
          x: 270,
          y: 200
        },
        %AgentSlot{
          id: 4,
          name: "scout-arch",
          capability: "scout",
          model: "sonnet",
          persona: "Investigates architecture.",
          x: 500,
          y: 200
        }
      ],
      next_id: 5,
      links: [
        %SpawnLink{from: 1, to: 2},
        %SpawnLink{from: 1, to: 3},
        %SpawnLink{from: 1, to: 4}
      ],
      rules:
        for(
          {w, l} <- [{2, 1}, {3, 1}, {4, 1}, {1, 2}, {1, 3}, {1, 4}],
          do: %CommRule{from: w, to: l}
        )
    },
    "review" => %TeamPreset{
      label: "Review Chain",
      color: "brand",
      team_name: "review-chain",
      strategy: "rest_for_one",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "architect",
          capability: "lead",
          model: "opus",
          persona: "Reviews designs and approves plans.",
          quality_gates: "mix compile --warnings-as-errors",
          x: 320,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "reviewer",
          capability: "reviewer",
          model: "sonnet",
          persona: "Code review for quality and correctness.",
          x: 80,
          y: 160
        },
        %AgentSlot{
          id: 3,
          name: "builder",
          capability: "builder",
          model: "sonnet",
          persona: "Implements features per approved design.",
          quality_gates: "mix compile --warnings-as-errors\nmix test",
          x: 320,
          y: 280
        },
        %AgentSlot{
          id: 4,
          name: "scout",
          capability: "scout",
          model: "haiku",
          persona: "Gathers context before implementation.",
          x: 560,
          y: 160
        }
      ],
      next_id: 5,
      links: [
        %SpawnLink{from: 1, to: 2},
        %SpawnLink{from: 1, to: 3},
        %SpawnLink{from: 1, to: 4}
      ],
      rules: [
        %CommRule{from: 4, to: 2},
        %CommRule{from: 2, to: 1},
        %CommRule{from: 3, to: 2},
        %CommRule{from: 1, to: 3},
        %CommRule{from: 3, to: 1, policy: "route", via: 2},
        %CommRule{from: 4, to: 1, policy: "deny"}
      ]
    },
    "mes" => %TeamPreset{
      label: "MES Factory",
      color: "warning",
      team_name: "mes",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "sonnet",
          persona: @mes_coordinator_persona,
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "lead",
          capability: "lead",
          model: "sonnet",
          persona: @mes_lead_persona,
          x: 220,
          y: 160
        },
        %AgentSlot{
          id: 3,
          name: "planner",
          capability: "builder",
          model: "sonnet",
          persona: @mes_planner_persona,
          x: 220,
          y: 300
        },
        %AgentSlot{
          id: 4,
          name: "researcher-1",
          capability: "scout",
          model: "sonnet",
          persona: @mes_researcher_persona,
          x: 40,
          y: 180
        },
        %AgentSlot{
          id: 5,
          name: "researcher-2",
          capability: "scout",
          model: "sonnet",
          persona: @mes_researcher_persona,
          x: 400,
          y: 180
        }
      ],
      next_id: 6,
      links: [
        %SpawnLink{from: 1, to: 2},
        %SpawnLink{from: 1, to: 3},
        %SpawnLink{from: 1, to: 4},
        %SpawnLink{from: 1, to: 5}
      ],
      rules: [
        %CommRule{from: 1, to: 2},
        %CommRule{from: 2, to: 1},
        %CommRule{from: 2, to: 3},
        %CommRule{from: 2, to: 4},
        %CommRule{from: 2, to: 5},
        %CommRule{from: 3, to: 2},
        %CommRule{from: 4, to: 2},
        %CommRule{from: 5, to: 2}
      ]
    },
    "planning_a" => %TeamPreset{
      label: "Planning Mode A",
      color: "violet",
      team_name: "planning",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "sonnet",
          persona:
            "Planning Mode A coordinator. Mediates all communication between architect and reviewer.",
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "architect",
          capability: "builder",
          model: "sonnet",
          persona: "Designs architecture decisions and proposals.",
          x: 40,
          y: 200
        },
        %AgentSlot{
          id: 3,
          name: "reviewer",
          capability: "scout",
          model: "sonnet",
          persona: "Reviews architecture proposals for correctness and completeness.",
          x: 400,
          y: 200
        }
      ],
      next_id: 4,
      links: [%SpawnLink{from: 1, to: 2}, %SpawnLink{from: 1, to: 3}],
      rules: [
        %CommRule{from: 1, to: 2},
        %CommRule{from: 2, to: 1},
        %CommRule{from: 1, to: 3},
        %CommRule{from: 3, to: 1}
      ]
    },
    "planning_b" => %TeamPreset{
      label: "Planning Mode B",
      color: "violet",
      team_name: "planning",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "sonnet",
          persona:
            "Planning Mode B coordinator. Mediates all communication between analyst and designer.",
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "analyst",
          capability: "builder",
          model: "sonnet",
          persona: "Analyzes requirements and produces functional specifications.",
          x: 40,
          y: 200
        },
        %AgentSlot{
          id: 3,
          name: "designer",
          capability: "builder",
          model: "sonnet",
          persona: "Designs implementation approach from functional specs.",
          x: 400,
          y: 200
        }
      ],
      next_id: 4,
      links: [%SpawnLink{from: 1, to: 2}, %SpawnLink{from: 1, to: 3}],
      rules: [
        %CommRule{from: 1, to: 2},
        %CommRule{from: 2, to: 1},
        %CommRule{from: 1, to: 3},
        %CommRule{from: 3, to: 1}
      ]
    },
    "planning_c" => %TeamPreset{
      label: "Planning Mode C",
      color: "violet",
      team_name: "planning",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %AgentSlot{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "sonnet",
          persona:
            "Planning Mode C coordinator. Mediates all communication between planner and architect.",
          x: 220,
          y: 20
        },
        %AgentSlot{
          id: 2,
          name: "planner",
          capability: "builder",
          model: "sonnet",
          persona: "Plans implementation roadmap with phases, sections, and tasks.",
          x: 40,
          y: 200
        },
        %AgentSlot{
          id: 3,
          name: "architect",
          capability: "builder",
          model: "sonnet",
          persona: "Validates and refines implementation plans for feasibility.",
          x: 400,
          y: 200
        }
      ],
      next_id: 4,
      links: [%SpawnLink{from: 1, to: 2}, %SpawnLink{from: 1, to: 3}],
      rules: [
        %CommRule{from: 1, to: 2},
        %CommRule{from: 2, to: 1},
        %CommRule{from: 1, to: 3},
        %CommRule{from: 3, to: 1}
      ]
    }
  }

  @doc "Return the list of all preset names."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@presets)

  @doc "Return preset metadata for UI rendering: [{name, label, color}]."
  @spec ui_list() :: [%{name: String.t(), label: String.t(), color: String.t()}]
  def ui_list do
    @presets
    |> Enum.map(fn {name, preset} ->
      %{name: name, label: preset.label, color: preset.color}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc "Fetch a preset by name."
  @spec fetch(String.t()) :: {:ok, TeamPreset.t()} | :error
  def fetch(name), do: Map.fetch(@presets, name)

  @doc """
  Apply a named preset to the workshop canvas state.

  Converts Ash embedded resource structs to plain maps at the boundary
  so CanvasState stays map-based. This conversion goes away naturally
  when /workshop fully replaces presets.
  """
  @spec apply(map(), String.t()) :: map()
  def apply(state, name) do
    case fetch(name) do
      {:ok, preset} ->
        state
        |> Map.put(:ws_team_name, preset.team_name)
        |> Map.put(:ws_strategy, preset.strategy)
        |> Map.put(:ws_default_model, preset.model)
        |> Map.put(:ws_agents, Enum.map(preset.agents, &to_canvas_map/1))
        |> Map.put(:ws_next_id, preset.next_id)
        |> Map.put(:ws_spawn_links, Enum.map(preset.links, &to_canvas_map/1))
        |> Map.put(:ws_comm_rules, Enum.map(preset.rules, &to_canvas_map/1))

      :error ->
        state
    end
  end

  @doc "Return agents sorted in depth-first spawn order per spawn links."
  @spec spawn_order([map()], [map()]) :: [map()]
  def spawn_order(agents, spawn_links) do
    has_parent = spawn_links |> Enum.map(& &1.to) |> MapSet.new()
    roots = Enum.reject(agents, fn agent -> MapSet.member?(has_parent, agent.id) end)
    children_map = Enum.group_by(spawn_links, & &1.from, & &1.to)
    walk(roots, agents, children_map)
  end

  defp walk([], _agents, _children), do: []

  defp walk([root | rest], agents, children) do
    kids =
      children
      |> Map.get(root.id, [])
      |> Enum.map(fn id -> Enum.find(agents, &(&1.id == id)) end)
      |> Enum.filter(& &1)

    [root | walk(kids ++ rest, agents, children)]
  end

  defp to_canvas_map(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp to_canvas_map(map) when is_map(map), do: map
end
