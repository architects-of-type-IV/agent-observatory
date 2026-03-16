defmodule IchorWeb.Components.MesFeedComponents do
  @moduledoc """
  Feed table components for MES project list.
  """

  use Phoenix.Component

  alias IchorWeb.Components.MesStatusComponents

  attr :projects, :list, required: true
  attr :selected, :any, default: nil

  def feed(assigns) do
    ~H"""
    <div :if={@projects == []} class="flex-1 flex items-center justify-center">
      <div class="ichor-empty">
        <p class="ichor-empty-title">No projects yet</p>
        <p class="ichor-empty-desc">
          The scheduler will spawn the first team shortly.
        </p>
      </div>
    </div>

    <div :if={@projects != []} class="flex-1 overflow-auto">
      <.feed_header />

      <div
        :for={project <- @projects}
        phx-click="mes_select_project"
        phx-value-id={project.id}
        class={[
          "grid grid-cols-[140px_1fr_150px_50px_90px] items-center px-3 py-2.5 border-b border-border/50 cursor-pointer transition-colors",
          feed_row_class(@selected, project)
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
          <MesStatusComponents.status_badge status={project.status} />
        </div>
      </div>
    </div>
    """
  end

  defp feed_header(assigns) do
    ~H"""
    <div class="grid grid-cols-[140px_1fr_150px_50px_90px] items-center px-3 py-1.5 border-b border-border bg-base/80 sticky top-0 z-10">
      <span class="text-[9px] font-semibold text-low uppercase tracking-wider">Module</span>
      <span class="text-[9px] font-semibold text-low uppercase tracking-wider">Project</span>
      <span class="text-[9px] font-semibold text-low uppercase tracking-wider">Topic</span>
      <span class="text-[9px] font-semibold text-low uppercase tracking-wider text-center">Ver</span>
      <span class="text-[9px] font-semibold text-low uppercase tracking-wider text-right">
        Status
      </span>
    </div>
    """
  end

  defp feed_row_class(nil, _project), do: "hover:bg-brand/[0.03]"

  defp feed_row_class(selected, project) when selected.id == project.id do
    "border-l-2 border-l-brand bg-brand/5 pl-2.5"
  end

  defp feed_row_class(_selected, _project), do: "hover:bg-brand/[0.03]"

  defp short_module(nil), do: ""

  defp short_module(module) when is_binary(module) do
    module |> String.split(".") |> List.last()
  end
end
