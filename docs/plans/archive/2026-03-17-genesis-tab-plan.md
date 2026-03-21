# Genesis Tab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Genesis tab to the MES view with master-detail artifact browsing and rendered markdown content.

**Architecture:** New `:genesis` tab value in the existing MES tab switcher. Genesis tab component renders a tabbed master-detail layout (Decisions / Requirements / Checkpoints / Roadmap). Content rendered via Earmark (already a dependency). New assigns for genesis sub-tab and selected artifact. LiveView subscribes to genesis signals for live updates.

**Tech Stack:** Phoenix LiveView, Earmark (markdown), Tailwind CSS, existing Ash Genesis resources.

---

### Task 1: Add Genesis to MES Tab Switcher

**Files:**
- Modify: `lib/ichor_web/components/mes_components.ex`
- Modify: `lib/ichor_web/live/dashboard_mes_handlers.ex`
- Modify: `lib/ichor_web/live/dashboard_state.ex`

**Step 1: Add `:genesis` to tab switcher list**

In `mes_components.ex`, change the tab_switcher `for` from `[:factory, :research]` to `[:factory, :research, :genesis]`.

**Step 2: Add genesis tab content area**

In `mes_view/1`, after the research tab `div`, add:

```elixir
<.genesis_tab
  :if={@mes_tab == :genesis}
  genesis_node={@genesis_node}
  genesis_sub_tab={@genesis_sub_tab}
  genesis_selected={@genesis_selected}
/>
```

This calls a new component (built in Task 2). For now, add a stub:

```elixir
defp genesis_tab(assigns) do
  ~H"""
  <div class="flex-1 overflow-hidden flex flex-col">
    <div class="p-8 text-muted text-sm">Genesis tab placeholder</div>
  </div>
  """
end
```

**Step 3: Add new assigns to dashboard_state.ex**

In the initial assigns map, add:

```elixir
genesis_sub_tab: :decisions,
genesis_selected: nil,
```

**Step 4: Handle genesis_sub_tab in mes_switch_tab**

The existing `mes_switch_tab` handler already works for the top-level tab. We need `genesis_switch_sub_tab` for the inner tabs. Add to `dashboard_mes_handlers.ex`:

```elixir
def dispatch("genesis_switch_tab", %{"tab" => tab}, socket) do
  assign(socket, :genesis_sub_tab, String.to_existing_atom(tab))
end

def dispatch("genesis_select_artifact", %{"type" => type, "id" => id}, socket) do
  assign(socket, :genesis_selected, {String.to_existing_atom(type), id})
end
```

**Step 5: Add new events to dashboard_live.ex event list**

Add `genesis_switch_tab genesis_select_artifact` to the `@mes_events` list.

**Step 6: Load genesis node when switching to genesis tab**

In the `mes_switch_tab` handler, add:

```elixir
defp maybe_load_genesis(:genesis, socket) do
  case socket.assigns.selected_mes_project do
    nil -> socket
    project -> assign(socket, :genesis_node, load_genesis_node(project))
  end
end
```

Call it from `dispatch("mes_switch_tab", ...)`.

**Step 7: Compile and verify**

Run: `mix compile --warnings-as-errors`

---

### Task 2: Genesis Tab Component with Sub-Tabs

**Files:**
- Create: `lib/ichor_web/components/genesis_tab_components.ex`
- Modify: `lib/ichor_web/components/mes_components.ex` (replace stub)

**Step 1: Create the genesis tab component module**

```elixir
defmodule IchorWeb.Components.GenesisTabComponents do
  use Phoenix.Component

  @sub_tabs [
    %{key: :decisions, label: "Decisions"},
    %{key: :requirements, label: "Requirements"},
    %{key: :checkpoints, label: "Checkpoints"},
    %{key: :roadmap, label: "Roadmap"}
  ]

  attr :genesis_node, :any, default: nil
  attr :genesis_sub_tab, :atom, default: :decisions
  attr :genesis_selected, :any, default: nil

  def genesis_tab(assigns) do
    assigns = assign(assigns, :sub_tabs, @sub_tabs)

    ~H"""
    <div class="flex-1 overflow-hidden flex flex-col">
      <div :if={!@genesis_node} class="flex-1 flex items-center justify-center">
        <p class="text-muted text-sm">Select a project with a Genesis node to view artifacts.</p>
      </div>

      <div :if={@genesis_node} class="flex-1 overflow-hidden flex flex-col">
        <%!-- Node controls bar --%>
        <.node_controls genesis_node={@genesis_node} />

        <%!-- Sub-tab bar --%>
        <.sub_tab_bar active={@genesis_sub_tab} sub_tabs={@sub_tabs} />

        <%!-- Tab content: master-detail --%>
        <div class="flex-1 overflow-hidden flex">
          <.tab_content
            genesis_node={@genesis_node}
            sub_tab={@genesis_sub_tab}
            selected={@genesis_selected}
          />
        </div>
      </div>
    </div>
    """
  end
end
```

**Step 2: Node controls bar**

Mode buttons (A/B/C), Gate Check, Generate DAG -- moved from the old genesis_panel. Horizontal bar above the sub-tabs.

```elixir
defp node_controls(assigns) do
  ~H"""
  <div class="flex items-center justify-between px-4 py-2 border-b border-border shrink-0 bg-surface/50">
    <div class="flex items-center gap-2">
      <span class="text-[10px] font-semibold text-low uppercase tracking-wider">
        {@genesis_node.title}
      </span>
      <span class="text-[9px] px-1.5 py-0.5 rounded bg-brand/10 text-brand font-bold uppercase">
        {to_string(@genesis_node.status)}
      </span>
    </div>

    <div class="flex items-center gap-1.5">
      <button
        :for={mode <- [{"a", "Mode A"}, {"b", "Mode B"}, {"c", "Mode C"}]}
        phx-click="mes_start_mode"
        phx-value-mode={elem(mode, 0)}
        phx-value-project-id={@genesis_node.mes_project_id}
        class="px-2 py-1 text-[9px] font-semibold rounded bg-brand/10 text-brand border border-brand/20 hover:bg-brand/20 transition-colors"
      >
        {elem(mode, 1)}
      </button>
      <button
        phx-click="mes_gate_check"
        phx-value-node-id={@genesis_node.id}
        class="px-2 py-1 text-[9px] font-semibold rounded bg-warning/10 text-warning border border-warning/20 hover:bg-warning/20 transition-colors"
      >
        Gate Check
      </button>
      <button
        phx-click="mes_generate_dag"
        phx-value-node-id={@genesis_node.id}
        class="px-2 py-1 text-[9px] font-semibold rounded bg-success/10 text-success border border-success/20 hover:bg-success/20 transition-colors"
      >
        Generate DAG
      </button>
    </div>
  </div>
  """
end
```

**Step 3: Sub-tab bar**

```elixir
defp sub_tab_bar(assigns) do
  ~H"""
  <div class="flex items-stretch border-b border-border shrink-0">
    <button
      :for={tab <- @sub_tabs}
      phx-click="genesis_switch_tab"
      phx-value-tab={tab.key}
      class={[
        "px-4 py-2.5 text-[10px] font-bold uppercase tracking-wider transition-colors",
        sub_tab_class(@active, tab.key)
      ]}
    >
      {tab.label}
    </button>
  </div>
  """
end

defp sub_tab_class(active, active), do: "bg-brand/10 text-brand border-b-2 border-brand"
defp sub_tab_class(_active, _tab), do: "text-muted hover:text-default hover:bg-surface/50"
```

**Step 4: Tab content dispatcher**

```elixir
defp tab_content(%{sub_tab: :decisions} = assigns) do
  items = Map.get(assigns.genesis_node, :adrs, [])
  assigns = assign(assigns, :items, items)
  ~H"""
  <.master_detail items={@items} selected={@genesis_selected} type="adr" />
  """
end

defp tab_content(%{sub_tab: :requirements} = assigns) do
  features = Map.get(assigns.genesis_node, :features, [])
  use_cases = Map.get(assigns.genesis_node, :use_cases, [])
  items = features ++ use_cases
  assigns = assign(assigns, :items, items)
  ~H"""
  <.master_detail items={@items} selected={@genesis_selected} type="requirement" />
  """
end

defp tab_content(%{sub_tab: :checkpoints} = assigns) do
  checkpoints = Map.get(assigns.genesis_node, :checkpoints, [])
  conversations = Map.get(assigns.genesis_node, :conversations, [])
  items = checkpoints ++ conversations
  assigns = assign(assigns, :items, items)
  ~H"""
  <.master_detail items={@items} selected={@genesis_selected} type="checkpoint" />
  """
end

defp tab_content(%{sub_tab: :roadmap} = assigns) do
  phases = Map.get(assigns.genesis_node, :phases, [])
  assigns = assign(assigns, :items, phases)
  ~H"""
  <.master_detail items={@items} selected={@genesis_selected} type="phase" />
  """
end
```

**Step 5: Compile and verify**

Run: `mix compile --warnings-as-errors`

---

### Task 3: Master-Detail Layout

**Files:**
- Modify: `lib/ichor_web/components/genesis_tab_components.ex`

**Step 1: Master-detail container**

```elixir
attr :items, :list, required: true
attr :selected, :any, default: nil
attr :type, :string, required: true

defp master_detail(assigns) do
  selected_item = find_selected(assigns.items, assigns.selected)
  assigns = assign(assigns, :selected_item, selected_item)

  ~H"""
  <div class="flex flex-1 overflow-hidden">
    <%!-- Left: item list --%>
    <div class={[
      "overflow-y-auto border-r border-border shrink-0",
      if(@selected_item, do: "w-72", else: "w-80")
    ]}>
      <div :if={@items == []} class="p-6 text-center">
        <p class="text-[11px] text-muted">No artifacts yet.</p>
      </div>

      <button
        :for={item <- @items}
        phx-click="genesis_select_artifact"
        phx-value-type={@type}
        phx-value-id={item.id}
        class={[
          "w-full flex items-center gap-3 px-4 py-3 text-left border-b border-border/50 transition-colors",
          item_selected_class(@selected, @type, item.id)
        ]}
      >
        <.item_label item={item} type={@type} />
      </button>
    </div>

    <%!-- Right: detail view --%>
    <div :if={@selected_item} class="flex-1 overflow-y-auto">
      <.artifact_detail item={@selected_item} type={@type} />
    </div>

    <div :if={!@selected_item && @items != []} class="flex-1 flex items-center justify-center">
      <p class="text-muted text-sm">Select an artifact to view its content.</p>
    </div>
  </div>
  """
end
```

**Step 2: Item label component**

```elixir
defp item_label(%{type: "adr"} = assigns) do
  ~H"""
  <span class="font-mono text-[10px] text-brand shrink-0">{@item.code}</span>
  <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
  <span class={["text-[9px] px-1.5 py-0.5 rounded font-bold uppercase", status_class(@item.status)]}>
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
  <span :if={Map.get(@item, :mode)} class="text-[9px] text-muted uppercase">{@item.mode}</span>
  """
end

defp item_label(%{type: "phase"} = assigns) do
  ~H"""
  <span class="font-mono text-[10px] text-success shrink-0">Phase {@item.number}</span>
  <span class="text-[11px] font-semibold truncate flex-1">{@item.title}</span>
  """
end
```

**Step 3: Helper functions**

```elixir
defp find_selected(_items, nil), do: nil
defp find_selected(items, {_type, id}), do: Enum.find(items, &(&1.id == id))
defp find_selected(_items, _), do: nil

defp item_selected_class({type_atom, id}, type_str, item_id)
     when to_string(type_atom) == type_str and id == item_id do
  "bg-brand/10 text-brand"
end
defp item_selected_class(_selected, _type, _id), do: "hover:bg-surface/50"

defp status_class(:accepted), do: "bg-success/15 text-success"
defp status_class(:proposed), do: "bg-brand/15 text-brand"
defp status_class(:rejected), do: "bg-danger/15 text-danger"
defp status_class(_), do: "bg-surface text-muted"
```

**Step 4: Compile and verify**

Run: `mix compile --warnings-as-errors`

---

### Task 4: Artifact Detail View with Markdown Rendering

**Files:**
- Modify: `lib/ichor_web/components/genesis_tab_components.ex`

**Step 1: Detail view component**

```elixir
defp artifact_detail(assigns) do
  content = Map.get(assigns.item, :content) || ""
  rendered_html = render_markdown(content)
  assigns = assign(assigns, :rendered_html, rendered_html)

  ~H"""
  <div class="p-6">
    <%!-- Header --%>
    <div class="mb-6">
      <div class="flex items-center gap-3 mb-2">
        <span :if={Map.get(@item, :code)} class="font-mono text-sm text-brand font-bold">
          {@item.code}
        </span>
        <span
          :if={Map.get(@item, :status)}
          class={["text-[10px] px-2 py-0.5 rounded font-bold uppercase", status_class(@item.status)]}
        >
          {@item.status}
        </span>
      </div>
      <h2 class="text-lg font-bold text-high">{@item.title}</h2>
      <.artifact_meta item={@item} type={@type} />
    </div>

    <%!-- Rendered content --%>
    <div class="prose prose-invert prose-sm max-w-none">
      {Phoenix.HTML.raw(@rendered_html)}
    </div>
  </div>
  """
end
```

**Step 2: Artifact metadata (varies by type)**

```elixir
defp artifact_meta(%{type: "adr"} = assigns) do
  ~H"""
  <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
    <span :if={@item.parent_code}>Parent: <span class="text-brand font-mono">{@item.parent_code}</span></span>
    <span :if={@item.related_adr_codes != []}>
      Related: <span class="text-brand font-mono">{Enum.join(@item.related_adr_codes, ", ")}</span>
    </span>
    <span :if={@item.research_complete} class="text-success">Research complete</span>
  </div>
  """
end

defp artifact_meta(%{type: "requirement"} = assigns) do
  ~H"""
  <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
    <span :if={Map.get(@item, :feature_code)}>
      Feature: <span class="text-interactive font-mono">{@item.feature_code}</span>
    </span>
    <span :if={Map.get(@item, :adr_codes) && @item.adr_codes != []}>
      ADRs: <span class="text-brand font-mono">{Enum.join(@item.adr_codes, ", ")}</span>
    </span>
  </div>
  """
end

defp artifact_meta(%{type: "phase"} = assigns) do
  ~H"""
  <div class="flex flex-wrap gap-3 mt-2 text-[10px] text-muted">
    <span :if={Map.get(@item, :goals)}>Goals: <span class="text-default">{@item.goals}</span></span>
    <span :if={Map.get(@item, :governed_by)}>
      Governed by: <span class="text-brand font-mono">{@item.governed_by}</span>
    </span>
  </div>
  """
end

defp artifact_meta(_assigns) do
  ~H"""
  """
end
```

**Step 3: Markdown rendering helper**

```elixir
defp render_markdown(""), do: "<p class=\"text-muted italic\">No content yet.</p>"
defp render_markdown(nil), do: "<p class=\"text-muted italic\">No content yet.</p>"

defp render_markdown(content) do
  case Earmark.as_html(content, compact_output: true) do
    {:ok, html, _} -> html
    {:error, _, _} -> "<pre>#{Phoenix.HTML.html_escape(content)}</pre>"
  end
end
```

**Step 4: Add Tailwind typography plugin for `prose` classes**

Check if `@tailwindcss/typography` is already installed. If not, add to assets/package.json and tailwind config.

**Step 5: Compile and verify**

Run: `mix compile --warnings-as-errors`

---

### Task 5: Wire into MES Orchestrator and Remove Old Genesis Panel

**Files:**
- Modify: `lib/ichor_web/components/mes_components.ex`
- Modify: `lib/ichor_web/components/mes_detail_components.ex`

**Step 1: Add genesis tab content to mes_view**

Replace the genesis_tab stub in mes_components.ex with the real component call:

```elixir
alias IchorWeb.Components.GenesisTabComponents

# In mes_view:
<GenesisTabComponents.genesis_tab
  :if={@mes_tab == :genesis}
  genesis_node={@genesis_node}
  genesis_sub_tab={@genesis_sub_tab}
  genesis_selected={@genesis_selected}
/>
```

**Step 2: Remove genesis panel from detail sidebar**

In `mes_detail_components.ex`, remove the `MesGenesisComponents.genesis_panel` call. The genesis pipeline section is now in its own tab.

**Step 3: Pass new assigns through mes_view attrs**

Add `genesis_sub_tab` and `genesis_selected` attrs to `mes_view`.

**Step 4: Compile and verify**

Run: `mix compile --warnings-as-errors`

---

### Task 6: LiveView Signal Subscription for Real-Time Updates

**Files:**
- Modify: `lib/ichor_web/live/dashboard_info_handlers.ex`
- Modify: `lib/ichor_web/live/dashboard_mes_handlers.ex`

**Step 1: Subscribe to genesis signals**

In the LiveView init (or info_handlers), subscribe to `:genesis` signal category.

**Step 2: Handle genesis artifact signals**

When a genesis signal arrives (e.g., `:genesis_run_complete`, `:genesis_team_ready`), reload the genesis node if the current tab is `:genesis`:

```elixir
def handle_genesis_signal(%{mes_tab: :genesis} = assigns, _signal) do
  case assigns.genesis_node do
    nil -> assigns
    node -> %{assigns | genesis_node: reload_genesis_node(node.id)}
  end
end
```

**Step 3: Compile and verify**

Run: `mix compile --warnings-as-errors`
</content>
</invoke>