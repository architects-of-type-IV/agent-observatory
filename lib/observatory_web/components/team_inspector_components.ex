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
      class="inspector-drawer bg-[#18181b] border-t border-zinc-800 h-8 flex items-center justify-center"
    >
      <span class="text-[10px] text-zinc-600">Select a team to inspect</span>
    </div>

    <%!-- Populated drawer --%>
    <div
      :if={@inspected_teams != []}
      id="inspector-drawer"
      phx-hook="InspectorDrawer"
      class={"inspector-drawer bg-[#18181b] border-t border-zinc-800 flex flex-col #{size_class(@inspector_size)} #{if @inspector_maximized, do: "inspector-maximized"}"}
    >
      <div class="flex items-center justify-between px-3 py-1.5 border-b border-zinc-800 shrink-0">
        <div class="flex items-center gap-2">
          <span class="text-[10px] font-semibold text-zinc-500 uppercase tracking-wider">Inspector</span>
          <span class="text-[10px] text-zinc-600 font-mono">{length(@inspected_teams)} teams</span>
        </div>
        <div class="flex items-center gap-0.5">
          <button
            :for={size <- [:collapsed, :default, :maximized]}
            phx-click="set_inspector_size"
            phx-value-size={size}
            class={"px-1.5 py-0.5 rounded text-[10px] font-mono transition #{if @inspector_size == size, do: "text-zinc-200 bg-zinc-700", else: "text-zinc-600 hover:text-zinc-400"}"}
          >
            {size_label(size)}
          </button>
          <button
            phx-click="toggle_inspector_layout"
            class="px-1.5 py-0.5 text-[10px] font-mono text-zinc-600 hover:text-zinc-400 transition ml-1"
            title={
              if @inspector_layout == :horizontal, do: "Stack vertically", else: "Stack horizontally"
            }
          >
            {if @inspector_layout == :horizontal, do: "|||", else: "==="}
          </button>
          <button
            phx-click="toggle_maximize_inspector"
            class="px-1.5 py-0.5 text-[10px] font-mono text-zinc-600 hover:text-zinc-400 transition"
            title="Maximize"
          >
            {if @inspector_maximized, do: "[-]", else: "[+]"}
          </button>
          <button
            phx-click="close_all_inspector"
            class="px-1.5 py-0.5 text-[10px] font-mono text-zinc-600 hover:text-zinc-400 transition"
            title="Close all"
          >
            x
          </button>
        </div>
      </div>
      <div class={"flex-1 overflow-hidden flex #{if @inspector_layout == :horizontal, do: "flex-row", else: "flex-col"} gap-px bg-zinc-800/50"}>
        <.inspector_panel :for={team <- @inspected_teams} team={team} />
      </div>
    </div>
    """
  end

  attr :team, :map, required: true

  defp inspector_panel(assigns) do
    ~H"""
    <div class="flex-1 min-w-0 min-h-0 bg-[#18181b] flex flex-col overflow-hidden">
      <div class="flex items-center justify-between px-2 py-1 border-b border-zinc-800/50 shrink-0">
        <div class="flex items-center gap-2">
          <span class="text-[10px] font-semibold text-zinc-300 font-mono truncate">{@team[:name]}</span>
          <span class="text-[9px] text-zinc-600 font-mono">{length(@team[:members] || [])} agents</span>
        </div>
        <button
          phx-click="remove_from_inspector"
          phx-value-team={@team[:name]}
          class="text-zinc-600 hover:text-zinc-400 text-[10px] transition px-1"
        >
          x
        </button>
      </div>
      <div
        id={"inspector-panel-#{@team[:name]}"}
        phx-hook="AutoScrollPane"
        class="flex-1 overflow-y-auto p-1.5"
      >
        <div class="grid grid-cols-2 gap-1.5">
          <div
            :for={member <- @team[:members] || []}
            class="obs-inspector-panel"
          >
            <div class="flex items-center gap-1.5 ip-name">
              <div class={"w-1.5 h-1.5 rounded-full shrink-0 #{member_status_color(member)}"} />
              <span>{member[:name]}</span>
            </div>
            <div class="ip-output">
              <span :if={member[:status]} class={member_status_text(member[:status])}>{member[:status]}</span>
              <span :if={member[:agent_type]} class="text-zinc-600"> {member[:agent_type]}</span>
            </div>
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

  defp member_status_text("active"), do: "text-emerald-400"
  defp member_status_text("idle"), do: "text-zinc-500"
  defp member_status_text("ended"), do: "text-zinc-700"
  defp member_status_text(_), do: "text-zinc-600"
end
