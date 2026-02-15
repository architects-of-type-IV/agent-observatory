defmodule ObservatoryWeb.Components.TeamInspectorComponents do
  @moduledoc """
  Team inspector drawer components for real-time team monitoring.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardTeamHelpers

  attr :inspected_teams, :list, default: []
  attr :inspector_layout, :atom, default: :horizontal
  attr :inspector_maximized, :boolean, default: false
  attr :inspector_size, :atom, default: :default
  attr :now, :any, required: true

  def inspector_drawer(assigns) do
    ~H"""
    <%!-- Empty collapsed bar --%>
    <div
      :if={@inspected_teams == []}
      class="inspector-drawer bg-zinc-900/80 border-t border-zinc-800 h-8 flex items-center justify-center"
    >
      <span class="text-xs text-zinc-600">Select a team to inspect</span>
    </div>

    <%!-- Populated drawer --%>
    <div
      :if={@inspected_teams != []}
      id="inspector-drawer"
      phx-hook="InspectorDrawer"
      class={"inspector-drawer bg-zinc-900 border-t border-zinc-800 flex flex-col #{size_class(@inspector_size)} #{if @inspector_maximized, do: "inspector-maximized"}"}
    >
      <div class="flex items-center justify-between px-4 py-2 border-b border-zinc-800 shrink-0">
        <div class="flex items-center gap-3">
          <span class="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Inspector</span>
          <span class="text-xs text-zinc-600">{length(@inspected_teams)} teams</span>
        </div>
        <div class="flex items-center gap-1">
          <button
            :for={size <- [:collapsed, :default, :maximized]}
            phx-click="set_inspector_size"
            phx-value-size={size}
            class={"p-1 rounded text-xs transition #{if @inspector_size == size, do: "text-zinc-200 bg-zinc-700", else: "text-zinc-500 hover:text-zinc-300"}"}
          >
            {size_label(size)}
          </button>
          <button
            phx-click="toggle_inspector_layout"
            class="p-1 text-zinc-500 hover:text-zinc-300 transition ml-2"
            title={
              if @inspector_layout == :horizontal, do: "Stack vertically", else: "Stack horizontally"
            }
          >
            {if @inspector_layout == :horizontal, do: "|||", else: "==="}
          </button>
          <button
            phx-click="toggle_maximize_inspector"
            class="p-1 text-zinc-500 hover:text-zinc-300 transition"
            title="Maximize"
          >
            {if @inspector_maximized, do: "[-]", else: "[+]"}
          </button>
          <button
            phx-click="close_all_inspector"
            class="p-1 text-zinc-500 hover:text-zinc-300 transition"
            title="Close all"
          >
            x
          </button>
        </div>
      </div>
      <div class={"flex-1 overflow-hidden flex #{if @inspector_layout == :horizontal, do: "flex-row", else: "flex-col"} gap-px bg-zinc-800"}>
        <.inspector_panel :for={team <- @inspected_teams} team={team} />
      </div>
    </div>
    """
  end

  attr :team, :map, required: true

  defp inspector_panel(assigns) do
    ~H"""
    <div class="flex-1 min-w-0 min-h-0 bg-zinc-900 flex flex-col overflow-hidden">
      <div class="flex items-center justify-between px-3 py-1.5 border-b border-zinc-800 shrink-0">
        <span class="text-xs font-medium text-zinc-300 truncate">{@team[:name]}</span>
        <button
          phx-click="remove_from_inspector"
          phx-value-team={@team[:name]}
          class="text-zinc-600 hover:text-zinc-400 text-xs transition"
        >
          x
        </button>
      </div>
      <div
        id={"inspector-panel-#{@team[:name]}"}
        phx-hook="AutoScrollPane"
        class="flex-1 overflow-y-auto p-2"
      >
        <div class="flex flex-wrap gap-1">
          <div
            :for={member <- @team[:members] || []}
            class="flex items-center gap-1 text-xs text-zinc-400"
          >
            <div class={"w-1.5 h-1.5 rounded-full #{member_status_color(member)}"} />
            <span>{member[:name]}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp size_class(:collapsed), do: "h-8 overflow-hidden"
  defp size_class(:default), do: "h-80"
  defp size_class(:maximized), do: ""

  defp size_label(:collapsed), do: "_"
  defp size_label(:default), do: "[]"
  defp size_label(:maximized), do: "[=]"
end
