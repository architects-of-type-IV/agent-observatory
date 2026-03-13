defmodule IchorWeb.Components.MesComponents do
  @moduledoc """
  Components for the MES (Manufacturing Execution System) view.
  """

  use Phoenix.Component

  attr :projects, :list, required: true
  attr :scheduler_status, :map, required: true

  def mes_view(assigns) do
    ~H"""
    <div class="h-full overflow-auto p-4">
      <div class="max-w-7xl mx-auto">
        <%!-- Header --%>
        <div class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-lg font-bold text-high tracking-tight">MES</h1>
            <p class="text-xs text-muted mt-0.5">Manufacturing Execution System</p>
          </div>

          <div class="flex items-center gap-2 px-3 py-1.5 rounded bg-surface border border-subtle text-xs text-default">
            <span class="inline-block w-2 h-2 rounded-full bg-brand animate-pulse" />
            <span>Tick {@scheduler_status.tick}</span>
            <span class="text-muted">|</span>
            <span>{@scheduler_status.active_runs} active</span>
          </div>
        </div>

        <%!-- Projects List --%>
        <div :if={@projects == []} class="text-center py-20">
          <p class="text-muted text-sm">
            No projects yet. The scheduler will spawn the first team shortly.
          </p>
        </div>

        <div :if={@projects != []} class="space-y-3">
          <div
            :for={project <- @projects}
            class="group border border-subtle rounded-lg p-4 bg-surface hover:border-border transition-colors"
          >
            <div class="flex items-start justify-between gap-4">
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-1">
                  <h3 class="font-semibold text-high text-sm truncate">{project.title}</h3>
                  <.status_badge status={project.status} />
                </div>

                <p class="text-xs text-default mb-2">{project.description}</p>

                <div class="flex items-center gap-4 text-[11px] text-muted">
                  <span>
                    Subsystem: <span class="text-brand">{project.subsystem}</span>
                  </span>
                  <span>
                    Signals: <span class="text-default">{project.signal_interface}</span>
                  </span>
                  <span :if={project.team_name}>Team: {project.team_name}</span>
                </div>
              </div>

              <div class="flex items-center gap-2 shrink-0">
                <button
                  :if={project.status == :proposed}
                  phx-click="mes_pick_up"
                  phx-value-id={project.id}
                  class="px-3 py-1.5 text-xs font-medium rounded bg-brand text-high hover:opacity-90 transition-opacity"
                >
                  Pick Up
                </button>

                <button
                  :if={project.status == :compiled}
                  phx-click="mes_load_subsystem"
                  phx-value-id={project.id}
                  class="px-3 py-1.5 text-xs font-medium rounded bg-success text-high hover:opacity-90 transition-opacity"
                >
                  Load into BEAM
                </button>

                <span
                  :if={project.status == :loaded}
                  class="px-3 py-1.5 text-xs font-medium rounded bg-success/20 text-success"
                >
                  Live
                </span>

                <span
                  :if={project.status == :failed}
                  class="px-3 py-1.5 text-xs font-medium rounded bg-error/20 text-error"
                >
                  Failed
                </span>
              </div>
            </div>

            <div
              :if={project.build_log && project.status == :failed}
              class="mt-3 p-2 rounded bg-raised text-xs text-error font-mono whitespace-pre-wrap max-h-32 overflow-auto"
            >
              {project.build_log}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(%{status: :proposed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-info/20 text-info uppercase tracking-wider">
      Proposed
    </span>
    """
  end

  defp status_badge(%{status: :in_progress} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-brand/20 text-brand uppercase tracking-wider">
      Building
    </span>
    """
  end

  defp status_badge(%{status: :compiled} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-success/20 text-success uppercase tracking-wider">
      Compiled
    </span>
    """
  end

  defp status_badge(%{status: :loaded} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-success/20 text-success uppercase tracking-wider">
      Loaded
    </span>
    """
  end

  defp status_badge(%{status: :failed} = assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-error/20 text-error uppercase tracking-wider">
      Failed
    </span>
    """
  end

  defp status_badge(assigns) do
    ~H"""
    <span class="px-1.5 py-0.5 text-[10px] font-medium rounded bg-raised text-muted uppercase tracking-wider">
      {@status}
    </span>
    """
  end
end
