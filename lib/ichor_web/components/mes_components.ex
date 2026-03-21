defmodule IchorWeb.Components.MesComponents do
  @moduledoc """
  Orchestrator for the MES (Manufacturing Execution System) unified factory view.
  Delegates to sub-components for feed, detail, artifacts, and gate rendering.
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesArtifactComponents
  alias IchorWeb.Components.MesDetailComponents
  alias IchorWeb.Components.MesFactoryComponents
  alias IchorWeb.Components.MesFeedComponents
  alias IchorWeb.Components.MesGateComponents

  attr :projects, :list, required: true
  attr :scheduler_status, :map, required: true
  attr :selected, :any, default: nil
  attr :planning_project, :any, default: nil
  attr :gate_report, :any, default: nil
  attr :planning_sub_tab, :atom, default: :decisions
  attr :planning_selected, :any, default: nil

  def mes_view(assigns) do
    ~H"""
    <div class="h-full flex flex-col overflow-hidden">
      <.header scheduler_status={@scheduler_status} />
      <div class="flex flex-1 overflow-hidden">
        <%!-- Feed (left) --%>
        <div class={"flex-1 flex flex-col overflow-hidden #{if @selected, do: "max-w-sm", else: ""}"}>
          <MesFeedComponents.feed
            projects={@projects}
            selected={@selected}
            compact={@selected != nil}
          />
        </div>

        <%!-- Main content (center, when project selected) --%>
        <div :if={@selected} class="flex-1 flex flex-col overflow-hidden border-l border-border">
          <MesFactoryComponents.action_bar
            project={@selected}
            planning_project={@planning_project}
            reader_open={@planning_selected != nil}
          />

          <%!-- Gate report (if present) --%>
          <MesGateComponents.gate_report :if={@gate_report} report={@gate_report} />

          <div :if={@planning_project} class="flex-1 flex flex-col overflow-hidden">
            <MesFactoryComponents.tab_bar
              active={@planning_sub_tab}
              planning_project={@planning_project}
            />
            <div class="flex-1 flex overflow-hidden">
              <MesArtifactComponents.artifact_list
                :if={!@planning_selected}
                planning_project={@planning_project}
                sub_tab={@planning_sub_tab}
                selected={@planning_selected}
              />
              <MesArtifactComponents.reader_sidebar
                :if={@planning_selected}
                planning_project={@planning_project}
                selected={@planning_selected}
                sub_tab={@planning_sub_tab}
              />
            </div>
          </div>

          <div :if={!@planning_project} class="flex-1 flex items-center justify-center">
            <p class="text-muted text-sm">Launch Mode A to begin the planning pipeline.</p>
          </div>
        </div>

        <%!-- Metadata sidebar (right, ~200px, when project selected) --%>
        <MesDetailComponents.metadata_sidebar :if={@selected} project={@selected} />
      </div>
    </div>
    """
  end

  attr :scheduler_status, :map, required: true

  defp header(assigns) do
    ~H"""
    <div class="flex items-center justify-between px-3 py-2 border-b border-border shrink-0">
      <div>
        <h1 class="text-sm font-bold text-high tracking-tight">
          Manufacturing Execution System
        </h1>
        <p class="text-[10px] text-low uppercase tracking-wider font-semibold mt-0.5">
          Subsystem Production Line
        </p>
      </div>

      <.scheduler_controls scheduler_status={@scheduler_status} />
    </div>
    """
  end

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
        <span :if={!@paused} class="font-mono text-[10px]">
          {@scheduler_status.active_runs} active
        </span>
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
