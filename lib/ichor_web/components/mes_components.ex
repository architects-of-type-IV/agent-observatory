defmodule IchorWeb.Components.MesComponents do
  @moduledoc """
  Orchestrator for the MES (Manufacturing Execution System) view.
  Delegates to sub-components for feed, detail, and status rendering.
  """

  use Phoenix.Component

  alias IchorWeb.Components.GenesisTabComponents
  alias IchorWeb.Components.MesDetailComponents
  alias IchorWeb.Components.MesFeedComponents
  alias IchorWeb.Components.MesResearchComponents

  attr :projects, :list, required: true
  attr :scheduler_status, :map, required: true
  attr :selected, :any, default: nil
  attr :mes_tab, :atom, default: :factory
  attr :research_results, :list, default: []
  attr :research_episodes, :list, default: []
  attr :research_entities, :list, default: []
  attr :selected_research_item, :any, default: nil
  attr :genesis_nodes, :list, default: []
  attr :genesis_node, :any, default: nil
  attr :gate_report, :any, default: nil
  attr :genesis_sub_tab, :atom, default: :decisions
  attr :genesis_selected, :any, default: nil

  def mes_view(assigns) do
    ~H"""
    <div class="h-full flex flex-col overflow-hidden">
      <.header scheduler_status={@scheduler_status} mes_tab={@mes_tab} />

      <%!-- Content: Factory tab --%>
      <div :if={@mes_tab == :factory} class="flex flex-1 overflow-hidden">
        <div class="flex-1 flex flex-col overflow-hidden">
          <MesFeedComponents.feed projects={@projects} selected={@selected} />
        </div>

        <div
          :if={@selected}
          class="w-[400px] shrink-0 border-l border-border bg-zinc-900/50 overflow-y-auto"
        >
          <MesDetailComponents.project_detail
            project={@selected}
            genesis_node={@genesis_node}
            gate_report={@gate_report}
          />
        </div>
      </div>

      <%!-- Content: Research tab --%>
      <MesResearchComponents.research_tab
        :if={@mes_tab == :research}
        entities={@research_entities}
        episodes={@research_episodes}
        results={@research_results}
        selected={@selected_research_item}
      />

      <%!-- Content: Planning tab --%>
      <GenesisTabComponents.genesis_tab
        :if={@mes_tab == :genesis}
        genesis_nodes={@genesis_nodes}
        genesis_node={@genesis_node}
        genesis_sub_tab={@genesis_sub_tab}
        genesis_selected={@genesis_selected}
      />
    </div>
    """
  end

  attr :scheduler_status, :map, required: true
  attr :mes_tab, :atom, required: true

  defp header(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-3 py-2 border-b border-border shrink-0">
      <div class="flex items-center gap-4">
        <div>
          <h1 class="text-sm font-bold text-high tracking-tight">
            Manufacturing Execution System
          </h1>
          <p class="text-[10px] text-low uppercase tracking-wider font-semibold mt-0.5">
            Subsystem Production Line
          </p>
        </div>

        <.tab_switcher mes_tab={@mes_tab} />
      </div>

      <.scheduler_controls :if={@mes_tab == :factory} scheduler_status={@scheduler_status} />
    </div>
    """
  end

  attr :mes_tab, :atom, required: true

  defp tab_switcher(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5 rounded bg-surface border border-subtle p-0.5">
      <button
        :for={
          {tab, label} <- [{:factory, "Factory"}, {:research, "Research"}, {:genesis, "Planning"}]
        }
        phx-click="mes_switch_tab"
        phx-value-tab={tab}
        class={[
          "px-2.5 py-1 text-[10px] font-semibold rounded transition-colors",
          tab_class(@mes_tab, tab)
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  defp tab_class(active, active), do: "bg-brand/15 text-brand"
  defp tab_class(_active, _tab), do: "text-muted hover:text-default"

  attr :scheduler_status, :map, required: true

  defp scheduler_controls(assigns) do
    paused = Map.get(assigns.scheduler_status, :paused, false)
    assigns = assign(assigns, :paused, paused)

    ~H"""
    <div class="flex items-center gap-2">
      <div class="flex items-center gap-2 px-2.5 py-1 rounded bg-surface border border-subtle text-[11px] text-default">
        <span
          :if={!@paused}
          class="inline-block w-1.5 h-1.5 rounded-full bg-brand animate-pulse"
        />
        <span :if={@paused} class="inline-block w-1.5 h-1.5 rounded-full bg-warning" />
        <span class="font-mono text-[10px]">Tick {@scheduler_status.tick}</span>
        <span class="text-muted">|</span>
        <span :if={!@paused}>{@scheduler_status.active_runs} active</span>
        <span :if={@paused} class="text-warning">Paused</span>
      </div>

      <button
        phx-click="toggle_mes_scheduler"
        class={[
          "px-2.5 py-1 text-[11px] font-semibold rounded transition-colors",
          toggle_class(@paused)
        ]}
      >
        {toggle_label(@paused)}
      </button>
    </div>
    """
  end

  defp toggle_class(true), do: "bg-brand/15 text-brand hover:bg-brand/25"
  defp toggle_class(false), do: "bg-warning/15 text-warning hover:bg-warning/25"

  defp toggle_label(true), do: "Resume"
  defp toggle_label(false), do: "Pause"
end
