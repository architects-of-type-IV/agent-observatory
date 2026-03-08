defmodule ObservatoryWeb.Components.WorkshopComponents do
  @moduledoc """
  Presentation components for the Agent Workshop team builder.
  Canvas interaction is handled by the WorkshopCanvas JS hook.
  """

  use Phoenix.Component

  embed_templates "workshop_components/*"

  # ── Workshop View (canvas-based team builder) ─────────────

  attr :ws_agents, :list, required: true
  attr :ws_spawn_links, :list, required: true
  attr :ws_comm_rules, :list, required: true
  attr :ws_selected_agent, :any, default: nil
  attr :ws_team_name, :string, default: "alpha"
  attr :ws_strategy, :string, default: "one_for_one"
  attr :ws_default_model, :string, default: "sonnet"
  attr :ws_cwd, :string, default: ""
  attr :ws_blueprints, :list, default: []
  attr :ws_blueprint_id, :any, default: nil
  attr :ws_agent_types, :list, default: []
  attr :ws_editing_type, :any, default: nil

  def workshop_view(assigns)

  # ── Helpers ────────────────────────────────────────────────

  @cap_colors %{
    "builder" => {"#22d3ee", "obs-badge-cyan", "BLD"},
    "scout" => {"#34d399", "obs-badge-green", "SCT"},
    "reviewer" => {"#fbbf24", "obs-badge-amber", "REV"},
    "lead" => {"#a78bfa", "obs-badge-violet", "LEAD"},
    "coordinator" => {"#818cf8", "obs-badge-indigo", "COORD"}
  }

  def cap_dot(cap), do: elem(Map.get(@cap_colors, cap, {"#71717a", "obs-badge-zinc", "?"}), 0)
  def cap_badge(cap), do: elem(Map.get(@cap_colors, cap, {"#71717a", "obs-badge-zinc", "?"}), 1)
  def cap_abbr(cap), do: elem(Map.get(@cap_colors, cap, {"#71717a", "obs-badge-zinc", "?"}), 2)

  def comm_tag_class("allow"), do: "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
  def comm_tag_class("deny"), do: "bg-red-500/10 text-red-400 border border-red-500/20"
  def comm_tag_class("route"), do: "bg-violet-500/10 text-violet-400 border border-violet-500/20"
  def comm_tag_class(_), do: "bg-zinc-800 text-zinc-400"

  def find_agent(agents, id) do
    Enum.find(agents, fn a -> a.id == id end)
  end

  def spawn_tree_html(agents, spawn_links) do
    children_map = Enum.group_by(spawn_links, & &1.from, & &1.to)
    has_parent = MapSet.new(Enum.map(spawn_links, & &1.to))
    roots = Enum.filter(agents, fn a -> !MapSet.member?(has_parent, a.id) end)
    build_tree(roots, agents, children_map, 0)
  end

  defp build_tree([], _agents, _children, _depth), do: []

  defp build_tree(nodes, agents, children, depth) do
    Enum.flat_map(nodes, fn node ->
      kids =
        Map.get(children, node.id, [])
        |> Enum.map(fn kid_id -> Enum.find(agents, &(&1.id == kid_id)) end)
        |> Enum.filter(& &1)

      [{node, depth} | build_tree(kids, agents, children, depth + 1)]
    end)
  end
end
