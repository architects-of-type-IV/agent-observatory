defmodule ObservatoryWeb.Components.TeamTmuxComponents do
  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardTeamHelpers

  attr :inspected_teams, :list, required: true
  attr :output_mode, :atom, default: :all_live
  attr :agent_toggles, :map, default: %{}
  attr :live_events, :list, default: []
  attr :now, :any, required: true

  def tmux_view(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 bg-zinc-950 flex flex-col">
      <div class="flex items-center justify-between px-4 py-2 border-b border-zinc-800 bg-zinc-900 shrink-0">
        <div class="flex items-center gap-2">
          <span class="text-xs font-semibold text-zinc-400 uppercase tracking-wider">Tmux View</span>
          <div class="flex items-center gap-1 ml-4">
            <button
              :for={mode <- [:all_live, :leads_only, :all_agents]}
              phx-click="set_output_mode"
              phx-value-mode={mode}
              class={"text-xs px-2 py-0.5 rounded transition #{if @output_mode == mode, do: "bg-cyan-600/30 text-cyan-300 ring-1 ring-cyan-500/50", else: "bg-zinc-800 text-zinc-500 hover:text-zinc-300"}"}
            >
              {mode_label(mode)}
            </button>
          </div>
        </div>
        <button
          phx-click="toggle_maximize_inspector"
          class="text-xs text-zinc-500 hover:text-zinc-300 transition px-2 py-1"
        >
          Exit
        </button>
      </div>
      <div class={"flex-1 overflow-hidden grid gap-px bg-zinc-800 #{grid_class(length(@inspected_teams))}"}>
        <.tmux_pane
          :for={team <- @inspected_teams}
          team={team}
          events={filter_events_for_team(team, @live_events, @output_mode, @agent_toggles)}
          agent_toggles={@agent_toggles}
        />
      </div>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :events, :list, required: true
  attr :agent_toggles, :map, required: true

  defp tmux_pane(assigns) do
    ~H"""
    <div class="bg-zinc-950 flex flex-col overflow-hidden">
      <div class="flex items-center justify-between px-3 py-1.5 bg-zinc-900 border-b border-zinc-800 shrink-0">
        <span class="text-xs font-medium text-zinc-300">{@team[:name]}</span>
        <div class="flex items-center gap-2">
          <label
            :for={member <- @team[:members] || []}
            class="flex items-center gap-1 text-xs text-zinc-500 cursor-pointer"
          >
            <input
              type="checkbox"
              phx-click="toggle_agent_output"
              phx-value-agent_id={member[:agent_id]}
              checked={Map.get(@agent_toggles, member[:agent_id], true)}
              class="w-3 h-3 rounded bg-zinc-800 border-zinc-600 text-indigo-500 focus:ring-0"
            />
            <span>{member[:name]}</span>
          </label>
        </div>
      </div>
      <div
        id={"tmux-pane-#{@team[:name]}"}
        phx-hook="AutoScrollPane"
        class="flex-1 overflow-y-auto font-mono"
      >
        <.event_line :for={event <- @events} event={event} />
        <div :if={@events == []} class="flex items-center justify-center h-full">
          <span class="text-xs text-zinc-700">No events</span>
        </div>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  defp event_line(assigns) do
    ~H"""
    <div class={"flex items-center gap-2 px-2 py-0.5 text-xs hover:bg-zinc-900/50 #{tool_line_color(@event)}"}>
      <span class="text-zinc-600 w-16 shrink-0 font-mono">{compact_time(@event.inserted_at)}</span>
      <span class={"shrink-0 w-14 truncate #{tool_name_color(@event)}"}>{display_tool(@event)}</span>
      <span class="text-zinc-400 truncate">{event_summary(@event)}</span>
    </div>
    """
  end

  defp mode_label(:all_live), do: "All Live"
  defp mode_label(:leads_only), do: "Leads Only"
  defp mode_label(:all_agents), do: "All Agents"

  defp grid_class(1), do: "grid-cols-1"
  defp grid_class(2), do: "grid-cols-2"
  defp grid_class(3), do: "grid-cols-2"
  defp grid_class(n) when n >= 4, do: "grid-cols-2 lg:grid-cols-3"

  defp filter_events_for_team(team, events, mode, agent_toggles) do
    member_sids = team_member_sids(team) |> MapSet.new()

    events
    |> Enum.filter(fn e -> MapSet.member?(member_sids, e.session_id) end)
    |> filter_by_mode(mode, team)
    |> filter_by_toggles(agent_toggles)
    |> Enum.take(200)
  end

  defp filter_by_mode(events, :all_live, _team), do: events
  defp filter_by_mode(events, :all_agents, _team), do: events

  defp filter_by_mode(events, :leads_only, team) do
    lead_sids =
      (team[:members] || [])
      |> Enum.filter(fn m -> detect_role(team, m) == :lead end)
      |> Enum.map(& &1[:agent_id])
      |> MapSet.new()

    Enum.filter(events, fn e -> MapSet.member?(lead_sids, e.session_id) end)
  end

  defp filter_by_toggles(events, toggles) when map_size(toggles) == 0, do: events

  defp filter_by_toggles(events, toggles) do
    Enum.filter(events, fn e -> Map.get(toggles, e.session_id, true) end)
  end

  defp tool_name_color(%{hook_event_type: t}) when t in [:PreToolUse, :PostToolUse],
    do: "text-amber-400"

  defp tool_name_color(%{hook_event_type: :PostToolUseFailure}), do: "text-red-400"
  defp tool_name_color(%{hook_event_type: :SessionStart}), do: "text-emerald-400"
  defp tool_name_color(%{hook_event_type: :SessionEnd}), do: "text-zinc-500"
  defp tool_name_color(_), do: "text-zinc-500"

  defp tool_line_color(%{hook_event_type: :PostToolUseFailure}), do: "bg-red-950/20"
  defp tool_line_color(_), do: ""

  defp display_tool(%{tool_name: name}) when is_binary(name), do: name
  defp display_tool(%{hook_event_type: type}), do: Atom.to_string(type)
  defp display_tool(_), do: ""

  defp compact_time(dt) do
    Calendar.strftime(dt, "%H:%M:%S")
  rescue
    _ -> ""
  end
end
