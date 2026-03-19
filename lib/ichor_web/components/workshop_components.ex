defmodule IchorWeb.Components.WorkshopComponents do
  @moduledoc """
  Presentation components for the Agent Workshop team builder.
  Canvas interaction is handled by the WorkshopCanvas JS hook.
  """

  use Phoenix.Component

  embed_templates "workshop_components/*"

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

  @cap_colors %{
    "builder" => {"hsl(var(--ichor-role-builder))", "ichor-badge-cyan", "BLD"},
    "scout" => {"hsl(var(--ichor-role-scout))", "ichor-badge-green", "SCT"},
    "reviewer" => {"hsl(var(--ichor-role-reviewer))", "ichor-badge-amber", "REV"},
    "lead" => {"hsl(var(--ichor-role-lead))", "ichor-badge-violet", "LEAD"},
    "coordinator" => {"hsl(var(--ichor-role-coordinator))", "ichor-badge-indigo", "COORD"}
  }

  @default_cap {"hsl(var(--ichor-role-default))", "ichor-badge-zinc", "?"}

  def cap_dot(cap), do: elem(Map.get(@cap_colors, cap, @default_cap), 0)
  def cap_badge(cap), do: elem(Map.get(@cap_colors, cap, @default_cap), 1)
  def cap_abbr(cap), do: elem(Map.get(@cap_colors, cap, @default_cap), 2)

  def comm_tag_class("allow"), do: "bg-success/10 text-success border border-success/20"
  def comm_tag_class("deny"), do: "bg-error/10 text-error border border-error/20"
  def comm_tag_class("route"), do: "bg-violet/10 text-violet border border-violet/20"
  def comm_tag_class(_), do: "bg-raised text-default"

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
