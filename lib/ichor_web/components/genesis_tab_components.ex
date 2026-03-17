defmodule IchorWeb.Components.GenesisTabComponents do
  @moduledoc """
  Genesis planning tab for MES projects.
  Tabbed master-detail layout for browsing artifacts (ADRs, Features, UseCases, etc.)
  with full rendered markdown content.
  """

  use Phoenix.Component

  @sub_tabs [
    %{key: :decisions, label: "Decisions"},
    %{key: :requirements, label: "Requirements"},
    %{key: :checkpoints, label: "Checkpoints"},
    %{key: :roadmap, label: "Roadmap"}
  ]

  attr :genesis_nodes, :list, default: []
  attr :genesis_node, :any, default: nil
  attr :genesis_sub_tab, :atom, default: :decisions
  attr :genesis_selected, :any, default: nil

  def genesis_tab(assigns) do
    assigns = assign(assigns, :sub_tabs, @sub_tabs)

    ~H"""
    <div class="flex-1 overflow-hidden flex">
      <%!-- Left: node list --%>
      <div class="w-56 shrink-0 border-r border-border overflow-y-auto bg-surface/20">
        <div class="px-3 py-2 border-b border-border">
          <h3 class="text-[9px] font-bold text-low uppercase tracking-wider">Projects</h3>
        </div>

        <div :if={@genesis_nodes == []} class="p-4 text-center">
          <p class="text-[11px] text-muted">No planning pipelines yet.</p>
          <p class="text-[10px] text-muted mt-1">Launch Mode A from a project in Factory.</p>
        </div>

        <button
          :for={node <- @genesis_nodes}
          phx-click="genesis_select_node"
          phx-value-id={node.id}
          class={[
            "w-full px-3 py-2.5 text-left border-b border-border/50 transition-colors",
            node_list_class(@genesis_node, node.id)
          ]}
        >
          <div class="text-[11px] font-semibold truncate">{node.title}</div>
          <div class="flex items-center gap-2 mt-1">
            <span class={[
              "text-[8px] px-1 py-0.5 rounded font-bold uppercase",
              node_status_class(node.status)
            ]}>
              {to_string(node.status)}
            </span>
          </div>
        </button>
      </div>

      <%!-- Right: selected node content --%>
      <div class="flex-1 overflow-hidden flex flex-col">
        <div :if={!@genesis_node} class="flex-1 flex items-center justify-center">
          <p class="text-muted text-sm">Select a node to view its planning artifacts.</p>
        </div>

        <div :if={@genesis_node} class="flex-1 overflow-hidden flex flex-col">
          <.node_controls genesis_node={@genesis_node} />
          <.sub_tab_bar active={@genesis_sub_tab} sub_tabs={@sub_tabs} node={@genesis_node} />

          <div class="flex-1 overflow-hidden flex">
            <.tab_content
              genesis_node={@genesis_node}
              sub_tab={@genesis_sub_tab}
              selected={@genesis_selected}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Node Controls ───────────────────────────────────────────────

  defp node_controls(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-4 py-2 border-b border-border shrink-0 bg-surface/30">
      <div class="flex items-center gap-3">
        <h2 class="text-sm font-bold text-high">{@genesis_node.title}</h2>
        <span class="text-[9px] px-1.5 py-0.5 rounded bg-brand/10 text-brand font-bold uppercase tracking-wider">
          {to_string(@genesis_node.status)}
        </span>
      </div>

      <div class="flex items-center gap-1.5">
        <button
          :for={{key, label} <- [{"a", "A"}, {"b", "B"}, {"c", "C"}]}
          phx-click="mes_start_mode"
          phx-value-mode={key}
          phx-value-project-id={@genesis_node.mes_project_id}
          class="px-2.5 py-1 text-[9px] font-bold rounded bg-brand/10 text-brand border border-brand/20 hover:bg-brand/20 transition-colors"
        >
          Mode {label}
        </button>

        <span class="w-px h-4 bg-border mx-1" />

        <button
          phx-click="mes_gate_check"
          phx-value-node-id={@genesis_node.id}
          class="px-2.5 py-1 text-[9px] font-bold rounded bg-warning/10 text-warning border border-warning/20 hover:bg-warning/20 transition-colors"
        >
          Gate
        </button>
        <button
          phx-click="mes_generate_dag"
          phx-value-node-id={@genesis_node.id}
          class="px-2.5 py-1 text-[9px] font-bold rounded bg-success/10 text-success border border-success/20 hover:bg-success/20 transition-colors"
        >
          DAG
        </button>
      </div>
    </div>
    """
  end

  # ── Sub-Tab Bar ─────────────────────────────────────────────────

  defp sub_tab_bar(assigns) do
    ~H"""
    <div class="flex items-stretch border-b border-border shrink-0">
      <button
        :for={tab <- @sub_tabs}
        phx-click="genesis_switch_tab"
        phx-value-tab={tab.key}
        class={[
          "px-5 py-2.5 text-[10px] font-bold uppercase tracking-wider transition-colors",
          sub_tab_class(@active, tab.key)
        ]}
      >
        {tab.label}
        <span class={[
          "ml-1.5 text-[9px]",
          sub_tab_count_class(@active, tab.key)
        ]}>
          {tab_count(@node, tab.key)}
        </span>
      </button>
    </div>
    """
  end

  defp sub_tab_class(active, active), do: "text-brand border-b-2 border-brand bg-brand/5"
  defp sub_tab_class(_active, _tab), do: "text-muted hover:text-default hover:bg-surface/30"

  defp sub_tab_count_class(active, active), do: "text-brand/60"
  defp sub_tab_count_class(_active, _tab), do: "text-muted/50"

  defp tab_count(node, :decisions), do: length(Map.get(node, :adrs, []))

  defp tab_count(node, :requirements),
    do: length(Map.get(node, :features, [])) + length(Map.get(node, :use_cases, []))

  defp tab_count(node, :checkpoints),
    do: length(Map.get(node, :checkpoints, [])) + length(Map.get(node, :conversations, []))

  defp tab_count(node, :roadmap), do: length(Map.get(node, :phases, []))

  # ── Tab Content ─────────────────────────────────────────────────

  defp tab_content(%{sub_tab: :decisions} = assigns) do
    assigns = assign(assigns, :items, Map.get(assigns.genesis_node, :adrs, []))

    ~H"""
    <.master_detail items={@items} selected={@selected} type="adr" />
    """
  end

  defp tab_content(%{sub_tab: :requirements} = assigns) do
    features = Map.get(assigns.genesis_node, :features, [])
    use_cases = Map.get(assigns.genesis_node, :use_cases, [])
    assigns = assign(assigns, :items, features ++ use_cases)

    ~H"""
    <.master_detail items={@items} selected={@selected} type="requirement" />
    """
  end

  defp tab_content(%{sub_tab: :checkpoints} = assigns) do
    checkpoints = Map.get(assigns.genesis_node, :checkpoints, [])
    conversations = Map.get(assigns.genesis_node, :conversations, [])
    assigns = assign(assigns, :items, checkpoints ++ conversations)

    ~H"""
    <.master_detail items={@items} selected={@selected} type="checkpoint" />
    """
  end

  defp tab_content(%{sub_tab: :roadmap} = assigns) do
    assigns = assign(assigns, :items, Map.get(assigns.genesis_node, :phases, []))

    ~H"""
    <.master_detail items={@items} selected={@selected} type="phase" />
    """
  end

  # ── Master-Detail Layout ────────────────────────────────────────

  attr :items, :list, required: true
  attr :selected, :any, default: nil
  attr :type, :string, required: true

  defp master_detail(assigns) do
    selected_item = find_selected(assigns.items, assigns.selected)
    assigns = assign(assigns, :selected_item, selected_item)

    ~H"""
    <div class="flex flex-1 overflow-hidden">
      <div class={[
        "overflow-y-auto border-r border-border shrink-0",
        if(@selected_item, do: "w-72", else: "w-80")
      ]}>
        <div :if={@items == []} class="p-8 text-center">
          <p class="text-[11px] text-muted">No artifacts yet.</p>
        </div>

        <button
          :for={item <- @items}
          phx-click="genesis_select_artifact"
          phx-value-type={@type}
          phx-value-id={item.id}
          class={[
            "w-full flex items-center gap-3 px-4 py-3 text-left border-b border-border/50 transition-colors",
            item_class(@selected, @type, item.id)
          ]}
        >
          <.item_label item={item} type={@type} />
        </button>
      </div>

      <div :if={@selected_item} class="flex-1 overflow-y-auto">
        <.artifact_detail item={@selected_item} type={@type} />
      </div>

      <div :if={!@selected_item && @items != []} class="flex-1 flex items-center justify-center">
        <p class="text-muted text-sm">Select an artifact to view its content.</p>
      </div>
    </div>
    """
  end

  # ── Item Labels ─────────────────────────────────────────────────

  defp item_label(%{type: "adr"} = assigns) do
    ~H"""
    <span class="font-mono text-[10px] text-brand shrink-0">{@item.code}</span>
    <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
    <span class={[
      "text-[9px] px-1.5 py-0.5 rounded font-bold uppercase shrink-0",
      status_class(@item.status)
    ]}>
      {@item.status}
    </span>
    """
  end

  defp item_label(%{type: "requirement"} = assigns) do
    ~H"""
    <span class="font-mono text-[10px] text-interactive shrink-0">{@item.code}</span>
    <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
    """
  end

  defp item_label(%{type: "checkpoint"} = assigns) do
    ~H"""
    <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
    <span :if={Map.get(@item, :mode)} class="text-[9px] text-muted uppercase shrink-0">
      {@item.mode}
    </span>
    """
  end

  defp item_label(%{type: "phase"} = assigns) do
    ~H"""
    <span class="font-mono text-[10px] text-success shrink-0">P{@item.number}</span>
    <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
    """
  end

  # ── Artifact Detail ─────────────────────────────────────────────

  defp artifact_detail(assigns) do
    content = Map.get(assigns.item, :content) || ""
    assigns = assign(assigns, :rendered_html, render_markdown(content))

    ~H"""
    <div class="p-6 max-w-3xl">
      <div class="mb-6">
        <div class="flex items-center gap-3 mb-2">
          <span :if={Map.get(@item, :code)} class="font-mono text-sm text-brand font-bold">
            {@item.code}
          </span>
          <span
            :if={Map.get(@item, :status)}
            class={[
              "text-[10px] px-2 py-0.5 rounded font-bold uppercase",
              status_class(@item.status)
            ]}
          >
            {@item.status}
          </span>
        </div>
        <h2 class="text-lg font-bold text-high leading-tight">{@item.title}</h2>
        <.artifact_meta item={@item} type={@type} />
      </div>

      <div class="genesis-prose">
        {Phoenix.HTML.raw(@rendered_html)}
      </div>
    </div>
    """
  end

  defp artifact_meta(%{type: "adr"} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
      <span :if={@item.parent_code}>
        Parent: <span class="text-brand font-mono">{@item.parent_code}</span>
      </span>
      <span :if={@item.related_adr_codes != []}>
        Related: <span class="text-brand font-mono">{Enum.join(@item.related_adr_codes, ", ")}</span>
      </span>
      <span :if={@item.research_complete} class="text-success font-semibold">Research complete</span>
    </div>
    """
  end

  defp artifact_meta(%{type: "requirement"} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
      <span :if={Map.get(@item, :feature_code)}>
        Feature: <span class="text-interactive font-mono">{@item.feature_code}</span>
      </span>
      <span :if={Map.get(@item, :adr_codes, []) != []}>
        ADRs: <span class="text-brand font-mono">{Enum.join(@item.adr_codes, ", ")}</span>
      </span>
    </div>
    """
  end

  defp artifact_meta(%{type: "phase"} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
      <span :if={Map.get(@item, :goals)}>
        <span class="text-default">{@item.goals}</span>
      </span>
      <span :if={Map.get(@item, :governed_by)}>
        Governed by: <span class="text-brand font-mono">{@item.governed_by}</span>
      </span>
    </div>
    """
  end

  defp artifact_meta(assigns) do
    ~H"""
    <div></div>
    """
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp find_selected(_items, nil), do: nil
  defp find_selected(items, {_type, id}), do: Enum.find(items, &(&1.id == id))
  defp find_selected(_items, _), do: nil

  defp item_class(nil, _type, _id), do: "hover:bg-surface/50"

  defp item_class({type_atom, id}, type_str, item_id) do
    case to_string(type_atom) == type_str and id == item_id do
      true -> "bg-brand/10 text-brand"
      false -> "hover:bg-surface/50"
    end
  end

  defp item_class(_selected, _type, _id), do: "hover:bg-surface/50"

  defp status_class(:accepted), do: "bg-success/15 text-success"
  defp status_class(:proposed), do: "bg-brand/15 text-brand"
  defp status_class(:rejected), do: "bg-danger/15 text-danger"
  defp status_class(_), do: "bg-surface text-muted"

  defp node_list_class(nil, _id), do: "hover:bg-surface/50"

  defp node_list_class(%{id: selected_id}, id) when selected_id == id,
    do: "bg-brand/10 border-l-2 border-l-brand"

  defp node_list_class(_node, _id), do: "hover:bg-surface/50"

  defp node_status_class(:discover), do: "bg-brand/15 text-brand"
  defp node_status_class(:define), do: "bg-interactive/15 text-interactive"
  defp node_status_class(:build), do: "bg-warning/15 text-warning"
  defp node_status_class(:complete), do: "bg-success/15 text-success"
  defp node_status_class(_), do: "bg-surface text-muted"

  defp render_markdown(nil), do: "<p class=\"text-muted italic\">No content yet.</p>"
  defp render_markdown(""), do: "<p class=\"text-muted italic\">No content yet.</p>"

  defp render_markdown(content) do
    case Earmark.as_html(content, compact_output: true) do
      {:ok, html, _} ->
        html

      {:error, _, _} ->
        "<pre>#{content |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()}</pre>"
    end
  end
end
