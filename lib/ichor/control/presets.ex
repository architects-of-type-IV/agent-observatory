defmodule Ichor.Control.Presets do
  @moduledoc """
  Canonical Workshop blueprint presets and launch ordering.
  """

  @presets %{
    "dag" => %{
      team_name: "dag-execution",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "opus",
          permission: "default",
          persona:
            "Strategic DAG orchestrator. Assesses job graph, groups jobs by file scope, dispatches waves to lead. Owns operator communication. Handles failure strategy (retry/skip/abort).",
          file_scope: "",
          quality_gates: "",
          x: 220,
          y: 20
        },
        %{
          id: 2,
          name: "lead",
          capability: "lead",
          model: "sonnet",
          permission: "default",
          persona:
            "Tactical DAG executor. Claims jobs per coordinator dispatch, pre-reads target files, builds context-rich worker prompts, spawns workers via spawn_agent MCP, verifies done_when, reports to coordinator. Max 5 concurrent workers.",
          file_scope: "",
          quality_gates: "mix compile --warnings-as-errors",
          x: 220,
          y: 200
        }
      ],
      next_id: 3,
      links: [%{from: 1, to: 2}],
      rules: [
        %{from: 1, to: 2, policy: "allow", via: nil},
        %{from: 2, to: 1, policy: "allow", via: nil}
      ]
    },
    "solo" => %{
      team_name: "solo",
      strategy: "one_for_one",
      model: "opus",
      agents: [
        %{
          id: 1,
          name: "builder",
          capability: "builder",
          model: "opus",
          permission: "default",
          persona: "Full-stack implementation agent.",
          file_scope: "",
          quality_gates: "mix compile --warnings-as-errors",
          x: 200,
          y: 60
        }
      ],
      next_id: 2,
      links: [],
      rules: []
    },
    "research" => %{
      team_name: "research-squad",
      strategy: "one_for_all",
      model: "sonnet",
      agents: [
        %{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "opus",
          permission: "default",
          persona: "Orchestrates research across scouts.",
          file_scope: "",
          quality_gates: "mix compile --warnings-as-errors",
          x: 220,
          y: 20
        },
        %{
          id: 2,
          name: "scout-api",
          capability: "scout",
          model: "haiku",
          permission: "default",
          persona: "Investigates API patterns.",
          file_scope: "",
          quality_gates: "",
          x: 40,
          y: 200
        },
        %{
          id: 3,
          name: "scout-db",
          capability: "scout",
          model: "haiku",
          permission: "default",
          persona: "Investigates data models.",
          file_scope: "",
          quality_gates: "",
          x: 270,
          y: 200
        },
        %{
          id: 4,
          name: "scout-arch",
          capability: "scout",
          model: "sonnet",
          permission: "default",
          persona: "Investigates architecture.",
          file_scope: "",
          quality_gates: "",
          x: 500,
          y: 200
        }
      ],
      next_id: 5,
      links: [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}],
      rules:
        for(
          {w, l} <- [{2, 1}, {3, 1}, {4, 1}, {1, 2}, {1, 3}, {1, 4}],
          do: %{from: w, to: l, policy: "allow", via: nil}
        )
    },
    "review" => %{
      team_name: "review-chain",
      strategy: "rest_for_one",
      model: "sonnet",
      agents: [
        %{
          id: 1,
          name: "architect",
          capability: "lead",
          model: "opus",
          permission: "default",
          persona: "Reviews designs and approves plans.",
          file_scope: "",
          quality_gates: "mix compile --warnings-as-errors",
          x: 320,
          y: 20
        },
        %{
          id: 2,
          name: "reviewer",
          capability: "reviewer",
          model: "sonnet",
          permission: "default",
          persona: "Code review for quality and correctness.",
          file_scope: "",
          quality_gates: "",
          x: 80,
          y: 160
        },
        %{
          id: 3,
          name: "builder",
          capability: "builder",
          model: "sonnet",
          permission: "default",
          persona: "Implements features per approved design.",
          file_scope: "",
          quality_gates: "mix compile --warnings-as-errors\nmix test",
          x: 320,
          y: 280
        },
        %{
          id: 4,
          name: "scout",
          capability: "scout",
          model: "haiku",
          permission: "default",
          persona: "Gathers context before implementation.",
          file_scope: "",
          quality_gates: "",
          x: 560,
          y: 160
        }
      ],
      next_id: 5,
      links: [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}],
      rules: [
        %{from: 4, to: 2, policy: "allow", via: nil},
        %{from: 2, to: 1, policy: "allow", via: nil},
        %{from: 3, to: 2, policy: "allow", via: nil},
        %{from: 1, to: 3, policy: "allow", via: nil},
        %{from: 3, to: 1, policy: "route", via: 2},
        %{from: 4, to: 1, policy: "deny", via: nil}
      ]
    },
    "mes" => %{
      team_name: "mes-template",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [
        %{
          id: 1,
          name: "coordinator",
          capability: "coordinator",
          model: "sonnet",
          permission: "default",
          persona: "Owns MES run orchestration and final operator delivery.",
          file_scope: "",
          quality_gates: "",
          x: 220,
          y: 20
        },
        %{
          id: 2,
          name: "lead",
          capability: "lead",
          model: "sonnet",
          permission: "default",
          persona: "Dispatches research topics to scouts, collects results, forwards to planner.",
          file_scope: "",
          quality_gates: "",
          x: 220,
          y: 160
        },
        %{
          id: 3,
          name: "planner",
          capability: "builder",
          model: "sonnet",
          permission: "default",
          persona: "Expands chosen proposals into implementation briefs.",
          file_scope: "",
          quality_gates: "",
          x: 220,
          y: 300
        },
        %{
          id: 4,
          name: "researcher-1",
          capability: "scout",
          model: "sonnet",
          permission: "default",
          persona: "Researches assigned topic domain, sends proposal to lead.",
          file_scope: "",
          quality_gates: "",
          x: 40,
          y: 180
        },
        %{
          id: 5,
          name: "researcher-2",
          capability: "scout",
          model: "sonnet",
          permission: "default",
          persona: "Researches assigned topic domain, sends proposal to lead.",
          file_scope: "",
          quality_gates: "",
          x: 400,
          y: 180
        }
      ],
      next_id: 6,
      links: [
        %{from: 1, to: 2},
        %{from: 2, to: 4},
        %{from: 2, to: 5},
        %{from: 4, to: 2},
        %{from: 5, to: 2},
        %{from: 2, to: 3},
        %{from: 3, to: 1}
      ],
      rules: [
        %{from: 1, to: 2, policy: "allow", via: nil},
        %{from: 2, to: 1, policy: "allow", via: nil},
        %{from: 2, to: 3, policy: "allow", via: nil},
        %{from: 2, to: 4, policy: "allow", via: nil},
        %{from: 2, to: 5, policy: "allow", via: nil},
        %{from: 3, to: 1, policy: "allow", via: nil},
        %{from: 4, to: 2, policy: "allow", via: nil},
        %{from: 5, to: 2, policy: "allow", via: nil}
      ]
    }
  }

  @doc "Return the list of all preset names."
  @spec names() :: [String.t()]
  def names, do: Map.keys(@presets)

  @doc "Fetch a preset by name."
  @spec fetch(String.t()) :: {:ok, map()} | :error
  def fetch(name) do
    case Map.fetch(@presets, name) do
      {:ok, preset} -> {:ok, preset}
      :error -> :error
    end
  end

  @doc "Apply a named preset to the workshop state, returning the updated state."
  @spec apply(map(), String.t()) :: map()
  def apply(state, name) do
    case fetch(name) do
      {:ok, preset} ->
        state
        |> Map.put(:ws_team_name, preset.team_name)
        |> Map.put(:ws_strategy, preset.strategy)
        |> Map.put(:ws_default_model, preset.model)
        |> Map.put(:ws_agents, preset.agents)
        |> Map.put(:ws_next_id, preset.next_id)
        |> Map.put(:ws_spawn_links, preset.links)
        |> Map.put(:ws_comm_rules, preset.rules)

      :error ->
        state
    end
  end

  @doc "Return agents sorted in depth-first spawn order per spawn links."
  @spec spawn_order([map()], [map()]) :: [map()]
  def spawn_order(agents, spawn_links) do
    has_parent = MapSet.new(Enum.map(spawn_links, & &1.to))
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
end
