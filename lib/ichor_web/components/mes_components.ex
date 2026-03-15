defmodule IchorWeb.Components.MesComponents do
  @moduledoc """
  Components for the MES (Manufacturing Execution System) view.
  Compact feed with split detail panel.
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesResearchComponents

  attr :projects, :list, required: true
  attr :scheduler_status, :map, required: true
  attr :selected, :any, default: nil
  attr :mes_tab, :atom, default: :factory
  attr :research_results, :list, default: []
  attr :research_episodes, :list, default: []
  attr :research_entities, :list, default: []
  attr :selected_research_item, :any, default: nil

  def mes_view(assigns) do
    ~H"""
    <div class="h-full flex flex-col overflow-hidden">
      <%!-- Header --%>
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

          <%!-- Tab switcher --%>
          <div class="flex items-center gap-0.5 rounded bg-surface border border-subtle p-0.5">
            <button
              phx-click="mes_switch_tab"
              phx-value-tab="factory"
              class={[
                "px-2.5 py-1 text-[10px] font-semibold rounded transition-colors",
                if(@mes_tab == :factory,
                  do: "bg-brand/15 text-brand",
                  else: "text-muted hover:text-default"
                )
              ]}
            >
              Factory
            </button>
            <button
              phx-click="mes_switch_tab"
              phx-value-tab="research"
              class={[
                "px-2.5 py-1 text-[10px] font-semibold rounded transition-colors",
                if(@mes_tab == :research,
                  do: "bg-brand/15 text-brand",
                  else: "text-muted hover:text-default"
                )
              ]}
            >
              Research
            </button>
          </div>
        </div>

        <div :if={@mes_tab == :factory} class="flex items-center gap-2">
          <div class="flex items-center gap-2 px-2.5 py-1 rounded bg-surface border border-subtle text-[11px] text-default">
            <span
              :if={!Map.get(@scheduler_status, :paused, false)}
              class="inline-block w-1.5 h-1.5 rounded-full bg-brand animate-pulse"
            />
            <span
              :if={Map.get(@scheduler_status, :paused, false)}
              class="inline-block w-1.5 h-1.5 rounded-full bg-warning"
            />
            <span class="font-mono text-[10px]">Tick {@scheduler_status.tick}</span>
            <span class="text-muted">|</span>
            <span :if={!Map.get(@scheduler_status, :paused, false)}>
              {@scheduler_status.active_runs} active
            </span>
            <span :if={Map.get(@scheduler_status, :paused, false)} class="text-warning">
              Paused
            </span>
          </div>

          <button
            phx-click="toggle_mes_scheduler"
            class={[
              "px-2.5 py-1 text-[11px] font-semibold rounded transition-colors",
              if(Map.get(@scheduler_status, :paused, false),
                do: "bg-brand/15 text-brand hover:bg-brand/25",
                else: "bg-warning/15 text-warning hover:bg-warning/25"
              )
            ]}
          >
            {if Map.get(@scheduler_status, :paused, false), do: "Resume", else: "Pause"}
          </button>
        </div>
      </div>

      <%!-- Content: Factory tab --%>
      <div :if={@mes_tab == :factory} class="flex flex-1 overflow-hidden">
        <%!-- Left: Compact feed --%>
        <div class="flex-1 flex flex-col overflow-hidden">
          <div :if={@projects == []} class="flex-1 flex items-center justify-center">
            <div class="ichor-empty">
              <p class="ichor-empty-title">No projects yet</p>
              <p class="ichor-empty-desc">
                The scheduler will spawn the first team shortly.
              </p>
            </div>
          </div>

          <div :if={@projects != []} class="flex-1 overflow-auto">
            <%!-- Column headers --%>
            <div class="grid grid-cols-[140px_1fr_150px_50px_90px] items-center px-3 py-1.5 border-b border-border bg-base/80 sticky top-0 z-10">
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
                Module
              </span>
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
                Project
              </span>
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider">
                Topic
              </span>
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider text-center">
                Ver
              </span>
              <span class="text-[9px] font-semibold text-low uppercase tracking-wider text-right">
                Status
              </span>
            </div>

            <%!-- Rows --%>
            <div
              :for={project <- @projects}
              phx-click="mes_select_project"
              phx-value-id={project.id}
              class={[
                "grid grid-cols-[140px_1fr_150px_50px_90px] items-center px-3 py-2.5 border-b border-border/50 cursor-pointer transition-colors",
                if(@selected && @selected.id == project.id,
                  do: "border-l-2 border-l-brand bg-brand/5 pl-2.5",
                  else: "hover:bg-brand/[0.03]"
                )
              ]}
            >
              <span class="font-mono text-[10px] text-brand truncate pr-2">
                {short_module(project.subsystem)}
              </span>
              <span class="text-[11px] font-semibold text-high truncate pr-2">
                {project.title}
              </span>
              <span class="font-mono text-[10px] text-muted truncate pr-2">
                {project.topic}
              </span>
              <span class="font-mono text-[10px] text-muted text-center">
                {project.version}
              </span>
              <div class="flex justify-end">
                <.status_badge status={project.status} />
              </div>
            </div>
          </div>
        </div>

        <%!-- Right: Detail panel --%>
        <div
          :if={@selected}
          class="w-[400px] shrink-0 border-l border-border bg-zinc-900/50 overflow-y-auto"
        >
          <.project_detail project={@selected} />
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
    </div>
    """
  end

  defp project_detail(assigns) do
    ~H"""
    <div class="p-4">
      <%!-- Title + badge + action --%>
      <div class="flex items-start justify-between gap-3 mb-1">
        <h2 class="text-base font-bold text-high tracking-tight leading-tight">
          {@project.title}
        </h2>
        <div class="flex items-center gap-2 shrink-0">
          <.status_badge status={@project.status} />
          <.action_button project={@project} />
        </div>
      </div>

      <p class="font-mono text-[10px] text-brand mb-3">{@project.subsystem}</p>

      <p class="text-[11px] text-default leading-relaxed mb-4">{@project.description}</p>

      <%!-- Features --%>
      <.detail_section
        :if={@project.features != [] && @project.features != nil}
        label="Features"
      >
        <div class="flex flex-wrap gap-1">
          <span
            :for={f <- @project.features}
            class="text-[9px] px-1.5 py-0.5 rounded bg-interactive/10 text-interactive border border-interactive/15"
          >
            {f}
          </span>
        </div>
      </.detail_section>

      <%!-- Use Cases --%>
      <.detail_section
        :if={@project.use_cases != [] && @project.use_cases != nil}
        label="Use Cases"
      >
        <div class="flex flex-wrap gap-1">
          <span
            :for={uc <- @project.use_cases}
            class="text-[9px] px-1.5 py-0.5 rounded bg-cyan/10 text-cyan border border-cyan/15"
          >
            {uc}
          </span>
        </div>
      </.detail_section>

      <%!-- Signals Emitted --%>
      <.detail_section
        :if={@project.signals_emitted != [] && @project.signals_emitted != nil}
        label="Signals Emitted"
      >
        <div class="flex flex-wrap gap-1">
          <span
            :for={s <- @project.signals_emitted}
            class="font-mono text-[9px] px-1.5 py-0.5 rounded bg-brand/10 text-brand"
          >
            {s}
          </span>
        </div>
      </.detail_section>

      <%!-- Signals Subscribed --%>
      <.detail_section
        :if={@project.signals_subscribed != [] && @project.signals_subscribed != nil}
        label="Signals Subscribed"
      >
        <div class="flex flex-wrap gap-1">
          <span
            :for={s <- @project.signals_subscribed}
            class="font-mono text-[9px] px-1.5 py-0.5 rounded bg-cyan/10 text-cyan"
          >
            {s}
          </span>
        </div>
      </.detail_section>

      <%!-- Architecture --%>
      <.detail_section
        :if={@project.architecture && @project.architecture != ""}
        label="Architecture"
      >
        <div class="font-mono text-[10px] text-default p-2.5 rounded bg-surface border border-subtle whitespace-pre-wrap leading-relaxed">
          {@project.architecture}
        </div>
      </.detail_section>

      <%!-- Dependencies --%>
      <.detail_section
        :if={@project.dependencies != [] && @project.dependencies != nil}
        label="Dependencies"
      >
        <div class="flex flex-wrap gap-1">
          <span
            :for={d <- @project.dependencies}
            class="font-mono text-[9px] px-1.5 py-0.5 rounded bg-violet/10 text-violet"
          >
            {d}
          </span>
        </div>
      </.detail_section>

      <%!-- Build Log --%>
      <.detail_section
        :if={@project.build_log && @project.status == :failed}
        label="Build Log"
      >
        <div class="font-mono text-[10px] text-error p-2.5 rounded bg-error/5 border border-error/15 whitespace-pre-wrap max-h-40 overflow-auto">
          {@project.build_log}
        </div>
      </.detail_section>

      <%!-- Footer metadata --%>
      <div class="mt-4 pt-3 border-t border-border/50 flex flex-wrap gap-x-4 gap-y-1 text-[10px] text-muted">
        <span :if={@project.version}>
          <span class="text-low">v</span><span class="font-mono text-default">{@project.version}</span>
        </span>
        <span :if={@project.topic}>
          <span class="font-mono text-default">{@project.topic}</span>
        </span>
        <span :if={@project.team_name}>
          Team: <span class="text-default">{@project.team_name}</span>
        </span>
        <span :if={@project.signal_interface}>
          Interface: <span class="text-default">{@project.signal_interface}</span>
        </span>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp detail_section(assigns) do
    ~H"""
    <div class="mb-3">
      <h4 class="text-[9px] font-semibold text-low uppercase tracking-wider mb-1.5">{@label}</h4>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp action_button(%{project: %{status: :proposed}} = assigns) do
    ~H"""
    <button
      phx-click="mes_pick_up"
      phx-value-id={@project.id}
      class="px-2.5 py-1 text-[10px] font-semibold rounded bg-brand/15 text-brand hover:bg-brand/25 transition-colors"
    >
      Pick Up
    </button>
    """
  end

  defp action_button(%{project: %{status: :compiled}} = assigns) do
    ~H"""
    <button
      phx-click="mes_load_subsystem"
      phx-value-id={@project.id}
      class="px-2.5 py-1 text-[10px] font-semibold rounded bg-success/15 text-success hover:bg-success/25 transition-colors"
    >
      Load into BEAM
    </button>
    """
  end

  defp action_button(assigns) do
    ~H"""
    """
  end

  defp status_badge(%{status: :proposed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-info/15 text-info uppercase tracking-wider">
      Proposed
    </span>
    """
  end

  defp status_badge(%{status: :in_progress} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-brand/15 text-brand uppercase tracking-wider">
      Building
    </span>
    """
  end

  defp status_badge(%{status: :compiled} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-success/15 text-success uppercase tracking-wider">
      Compiled
    </span>
    """
  end

  defp status_badge(%{status: :loaded} = assigns) do
    ~H"""
    <span class="flex items-center gap-1 px-1.5 py-0.5 text-[9px] font-semibold rounded bg-success/15 text-success uppercase tracking-wider">
      <span class="w-1 h-1 rounded-full bg-success animate-pulse" /> Live
    </span>
    """
  end

  defp status_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-error/15 text-error uppercase tracking-wider">
      Failed
    </span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[9px] font-semibold rounded bg-raised text-muted uppercase tracking-wider">
      {@status}
    </span>
    """
  end

  defp short_module(nil), do: ""

  defp short_module(module) when is_binary(module) do
    module |> String.split(".") |> List.last()
  end
end
