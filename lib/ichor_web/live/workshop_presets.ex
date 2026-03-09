defmodule IchorWeb.WorkshopPresets do
  @moduledoc """
  Preset team configurations and launch logic for the Workshop.
  """

  import Phoenix.Component, only: [assign: 3]

  @dag_lead %{id: 1, name: "lead", capability: "lead", model: "opus", permission: "default",
    persona: "DAG pipeline lead. Manages spawning, conflict resolution, verification, and GC.",
    file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 220, y: 20}

  @dag_workers (for {i, x} <- [{2, 40}, {3, 270}, {4, 500}] do
    %{id: i, name: "worker-#{i - 1}", capability: "builder", model: "sonnet", permission: "default",
      persona: "", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: x, y: 200}
  end)

  @presets %{
    "dag" => %{
      team_name: "dag-pipeline",
      strategy: "one_for_one",
      model: "sonnet",
      agents: [@dag_lead | @dag_workers],
      next_id: 5,
      links: [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}],
      rules: (for {w, l} <- [{2, 1}, {3, 1}, {4, 1}, {1, 2}, {1, 3}, {1, 4}], do: %{from: w, to: l, policy: "allow", via: nil}) ++
             (for {a, b} <- [{2, 3}, {3, 2}, {2, 4}, {4, 2}, {3, 4}, {4, 3}], do: %{from: a, to: b, policy: "deny", via: nil})
    },
    "solo" => %{
      team_name: "solo",
      strategy: "one_for_one",
      model: "opus",
      agents: [%{id: 1, name: "builder", capability: "builder", model: "opus", permission: "default",
        persona: "Full-stack implementation agent.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 200, y: 60}],
      next_id: 2,
      links: [],
      rules: []
    },
    "research" => %{
      team_name: "research-squad",
      strategy: "one_for_all",
      model: "sonnet",
      agents: [
        %{id: 1, name: "coordinator", capability: "coordinator", model: "opus", permission: "default",
          persona: "Orchestrates research across scouts.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 220, y: 20},
        %{id: 2, name: "scout-api", capability: "scout", model: "haiku", permission: "default",
          persona: "Investigates API patterns.", file_scope: "", quality_gates: "", x: 40, y: 200},
        %{id: 3, name: "scout-db", capability: "scout", model: "haiku", permission: "default",
          persona: "Investigates data models.", file_scope: "", quality_gates: "", x: 270, y: 200},
        %{id: 4, name: "scout-arch", capability: "scout", model: "sonnet", permission: "default",
          persona: "Investigates architecture.", file_scope: "", quality_gates: "", x: 500, y: 200}
      ],
      next_id: 5,
      links: [%{from: 1, to: 2}, %{from: 1, to: 3}, %{from: 1, to: 4}],
      rules: (for {w, l} <- [{2, 1}, {3, 1}, {4, 1}, {1, 2}, {1, 3}, {1, 4}], do: %{from: w, to: l, policy: "allow", via: nil})
    },
    "review" => %{
      team_name: "review-chain",
      strategy: "rest_for_one",
      model: "sonnet",
      agents: [
        %{id: 1, name: "architect", capability: "lead", model: "opus", permission: "default",
          persona: "Reviews designs and approves plans.", file_scope: "", quality_gates: "mix compile --warnings-as-errors", x: 320, y: 20},
        %{id: 2, name: "reviewer", capability: "reviewer", model: "sonnet", permission: "default",
          persona: "Code review for quality and correctness.", file_scope: "", quality_gates: "", x: 80, y: 160},
        %{id: 3, name: "builder", capability: "builder", model: "sonnet", permission: "default",
          persona: "Implements features per approved design.", file_scope: "", quality_gates: "mix compile --warnings-as-errors\nmix test", x: 320, y: 280},
        %{id: 4, name: "scout", capability: "scout", model: "haiku", permission: "default",
          persona: "Gathers context before implementation.", file_scope: "", quality_gates: "", x: 560, y: 160}
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
    }
  }

  @spec apply(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def apply(socket, name) do
    case Map.get(@presets, name) do
      nil -> socket
      preset ->
        socket
        |> assign(:ws_team_name, preset.team_name)
        |> assign(:ws_strategy, preset.strategy)
        |> assign(:ws_default_model, preset.model)
        |> assign(:ws_agents, preset.agents)
        |> assign(:ws_next_id, preset.next_id)
        |> assign(:ws_spawn_links, preset.links)
        |> assign(:ws_comm_rules, preset.rules)
    end
  end

  # ── Spawn Order (topological sort for launch) ──────────────

  @spec spawn_order([map()], [map()]) :: [map()]
  def spawn_order(agents, spawn_links) do
    has_parent = MapSet.new(Enum.map(spawn_links, & &1.to))
    roots = Enum.reject(agents, fn a -> MapSet.member?(has_parent, a.id) end)
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
