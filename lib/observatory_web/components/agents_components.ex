defmodule ObservatoryWeb.Components.AgentsComponents do
  @moduledoc """
  Agents/teams view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.DashboardTeamHelpers

  attr :teams, :list, required: true
  attr :active_tasks, :list, required: true
  attr :selected_agent, :map, default: nil
  attr :mailbox_counts, :map, required: true
  attr :now, :any, required: true

  def agents_view(assigns) do
    ~H"""
    <div class="p-4">
      <.empty_state
        :if={@teams == []}
        title="No teams active yet"
        description="Teams appear when agents use TeamCreate tool to spawn teammates"
      />

      <div :if={@teams != []} class="grid grid-cols-2 gap-4 min-w-0">
        <div
          :for={team <- @teams}
          class="p-4 rounded-lg border border-zinc-800 bg-zinc-900/50"
        >
          <div class="mb-3">
            <div class="flex items-center justify-between mb-1">
              <h3 class="text-sm font-semibold text-zinc-200">{team.name}</h3>
            </div>
            <p :if={team.description} class="text-xs text-zinc-500 mb-2">{team.description}</p>

            <%!-- Team broadcast input --%>
            <div phx-update="ignore" id={"broadcast-form-#{team.name}"} phx-hook="ClearFormOnSubmit">
              <form phx-submit="send_team_broadcast" class="flex gap-1">
                <input type="hidden" name="team" value={team.name} />
                <input
                  type="text"
                  name="content"
                  placeholder="Broadcast to team..."
                  class="flex-1 bg-zinc-800 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-300 placeholder-zinc-600 focus:border-cyan-500 focus:ring-0 focus:outline-none"
                />
                <button
                  type="submit"
                  class="px-2 py-1 bg-cyan-600/20 text-cyan-400 rounded text-xs hover:bg-cyan-600/30 transition"
                >
                  Send
                </button>
              </form>
            </div>
          </div>

          <% task_total = length(team.tasks) %>
          <% task_done = Enum.count(team.tasks, fn t -> t[:status] == "completed" end) %>
          <div :if={task_total > 0} class="mb-3">
            <div class="flex items-center justify-between text-xs text-zinc-500 mb-1">
              <span>Task Progress</span>
              <span>{task_done}/{task_total}</span>
            </div>
            <div class="h-2 bg-zinc-800 rounded-full overflow-hidden">
              <div
                class="h-full bg-emerald-500 rounded-full transition-all"
                style={"width: #{if task_total > 0, do: round(task_done / task_total * 100), else: 0}%"}
              >
              </div>
            </div>
          </div>

          <div class="space-y-2">
            <h4 class="text-xs font-semibold text-zinc-500 uppercase tracking-wider">Members</h4>
            <div
              :for={member <- team.members}
              phx-click="select_agent"
              phx-value-id={member[:agent_id]}
              class={"p-2 rounded bg-zinc-800/50 border hover:border-zinc-700 transition cursor-pointer #{if member[:status] == :idle, do: "opacity-60", else: ""} #{if @selected_agent && @selected_agent[:agent_id] == member[:agent_id], do: "border-indigo-500/40 bg-zinc-800/80", else: "border-zinc-800"}"}
            >
              <div class="flex items-center gap-2 mb-1">
                <span class={"w-2 h-2 rounded-full shrink-0 #{member_status_color(member)}"}></span>
                <span class="text-xs font-semibold text-zinc-300">{member[:name] || "?"}</span>
                <span :if={member[:agent_type]} class="text-xs text-zinc-600 ml-auto">
                  {member[:agent_type]}
                </span>
                <.model_badge model={member[:model]} />
                <% perm_mode = format_permission_mode(member[:permission_mode]) %>
                <span
                  :if={perm_mode}
                  class="text-xs font-mono px-1.5 py-0.5 rounded bg-yellow-500/15 text-yellow-400 border border-yellow-500/30"
                >
                  {perm_mode}
                </span>
                <% task_count = Enum.count(@active_tasks, fn t -> t[:owner] == member[:name] end) %>
                <button
                  :if={task_count > 0}
                  phx-click="filter_agent_tasks"
                  phx-value-session_id={member[:agent_id]}
                  class="inline-flex items-center justify-center px-1.5 min-w-[1.25rem] h-4 text-xs font-semibold text-white bg-blue-500 rounded-full hover:bg-blue-600 transition"
                  title="View tasks"
                >
                  {task_count}
                </button>
                <% unread = Map.get(@mailbox_counts, member[:agent_id], 0) %>
                <span
                  :if={unread > 0}
                  class="inline-flex items-center justify-center px-1.5 min-w-[1.25rem] h-4 text-xs font-semibold text-white bg-indigo-500 rounded-full"
                >
                  {unread}
                </span>
              </div>
              <div class="flex items-center gap-2 ml-4 text-xs text-zinc-500 mb-1">
                <span :if={member[:cwd]}>
                  {abbreviate_cwd(member[:cwd])}
                </span>
                <span :if={member[:uptime]}>
                  | {format_uptime(member[:uptime])}
                </span>
                <span :if={member[:latest_event]}>
                  | {relative_time(member[:latest_event].inserted_at, @now)}
                </span>
                <span :if={member[:event_count] && member[:event_count] > 0}>
                  | {member[:event_count]} events
                </span>
              </div>
              <div :if={member[:current_tool]} class="ml-4 mb-1 text-xs text-blue-400">
                Running: {member[:current_tool].tool_name} ({member[:current_tool].elapsed}s)
              </div>
              <div :if={member[:failure_rate] && member[:failure_rate] > 0} class="ml-4 mb-1">
                <% fail_pct = Float.round(member[:failure_rate] * 100, 0) %>
                <span class={"text-xs px-1.5 py-0.5 rounded #{if fail_pct > 10, do: "bg-red-500/20 text-red-400", else: "bg-amber-500/20 text-amber-400"}"}>
                  {fail_pct}% failures
                </span>
              </div>

              <%!-- Health warnings --%>
              <.health_warnings issues={member[:health_issues] || []} />

              <%!-- Agent messaging controls --%>
              <div :if={member[:agent_id]} class="ml-4 space-y-1">
                <div
                  phx-update="ignore"
                  id={"agent-msg-#{member[:agent_id]}"}
                  phx-hook="ClearFormOnSubmit"
                >
                  <form phx-submit="send_agent_message" class="flex gap-1">
                    <input type="hidden" name="session_id" value={member[:agent_id]} />
                    <input
                      type="text"
                      name="content"
                      placeholder="Send message..."
                      class="flex-1 bg-zinc-900 border border-zinc-700 rounded px-2 py-1 text-xs text-zinc-300 placeholder-zinc-700 focus:border-indigo-500 focus:ring-0 focus:outline-none"
                    />
                    <button
                      type="submit"
                      class="px-2 py-1 bg-indigo-600/20 text-indigo-400 rounded text-xs hover:bg-indigo-600/30 transition"
                      title="Send message"
                    >
                      Send
                    </button>
                  </form>
                </div>
                <div class="flex gap-1">
                  <button
                    phx-click="filter_agent"
                    phx-value-session_id={member[:agent_id]}
                    class="flex-1 px-2 py-1 bg-zinc-700/50 text-zinc-400 rounded text-xs hover:bg-zinc-700 transition"
                    title="View events"
                  >
                    Events
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
