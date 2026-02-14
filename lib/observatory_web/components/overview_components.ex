defmodule ObservatoryWeb.Components.OverviewComponents do
  @moduledoc """
  Overview view component for the Observatory dashboard.
  Displays system statistics and recent activity.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers

  attr :teams, :list, required: true
  attr :active_tasks, :list, required: true
  attr :messages, :list, required: true
  attr :visible_events, :list, required: true
  attr :events, :list, required: true
  attr :errors, :list, required: true
  attr :total_sessions, :integer, required: true
  attr :sessions, :list, required: true
  attr :now, :any, required: true

  def overview_view(assigns) do
    ~H"""
    <div class="p-6">
      <h2 class="text-lg font-semibold text-zinc-300 mb-6">System Overview</h2>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <%!-- Active Teams Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Active Teams</h3>
            <button phx-click="set_view" phx-value-mode="agents" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <div class="text-3xl font-bold text-zinc-200">{length(@teams)}</div>
          <p class="text-xs text-zinc-600 mt-1">
            {Enum.sum(Enum.map(@teams, fn t -> length(t.members) end))} agents total
          </p>
        </div>

        <%!-- Active Tasks Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Tasks</h3>
            <button phx-click="set_view" phx-value-mode="tasks" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <% task_count = length(@active_tasks) %>
          <% completed = Enum.count(@active_tasks, fn t -> t[:status] == "completed" end) %>
          <div class="text-3xl font-bold text-zinc-200">{task_count}</div>
          <div class="mt-2">
            <div class="flex items-center justify-between text-xs text-zinc-500 mb-1">
              <span>Progress</span>
              <span>{completed}/{task_count}</span>
            </div>
            <div class="h-2 bg-zinc-800 rounded-full overflow-hidden">
              <div
                class="h-full bg-emerald-500 rounded-full transition-all"
                style={"width: #{if task_count > 0, do: round(completed / task_count * 100), else: 0}%"}
              >
              </div>
            </div>
          </div>
        </div>

        <%!-- Messages Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Messages</h3>
            <button phx-click="set_view" phx-value-mode="messages" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <div class="text-3xl font-bold text-zinc-200">{length(@messages)}</div>
          <p class="text-xs text-zinc-600 mt-1">Inter-agent coordination</p>
        </div>

        <%!-- Events Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Events</h3>
            <button phx-click="set_view" phx-value-mode="feed" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <div class="text-3xl font-bold text-zinc-200">{length(@visible_events)}</div>
          <p class="text-xs text-zinc-600 mt-1">{length(@events)} total cached</p>
        </div>

        <%!-- Errors Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Errors</h3>
            <button phx-click="set_view" phx-value-mode="errors" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <div class={"text-3xl font-bold #{if length(@errors) > 0, do: "text-red-400", else: "text-zinc-200"}"}>{length(@errors)}</div>
          <p class="text-xs text-zinc-600 mt-1">Tool failures detected</p>
        </div>

        <%!-- Sessions Card --%>
        <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 hover:border-zinc-700 transition">
          <div class="flex items-center justify-between mb-2">
            <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Sessions</h3>
            <button phx-click="set_view" phx-value-mode="feed" class="text-xs text-indigo-400 hover:text-indigo-300">
              View →
            </button>
          </div>
          <div class="text-3xl font-bold text-zinc-200">{@total_sessions}</div>
          <p class="text-xs text-zinc-600 mt-1">
            {length(@sessions)} standalone
          </p>
        </div>
      </div>

      <%!-- Recent Activity Section --%>
      <div :if={length(@visible_events) > 0} class="mt-8">
        <div class="flex items-center justify-between mb-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Recent Activity</h3>
          <button phx-click="set_view" phx-value-mode="feed" class="text-xs text-indigo-400 hover:text-indigo-300">
            View all →
          </button>
        </div>
        <div class="space-y-1">
          <div :for={event <- Enum.take(@visible_events, 10)} class="flex items-center gap-2 px-3 py-2 rounded bg-zinc-900/30 hover:bg-zinc-900/60 transition text-xs">
            <% {bg, _border, _text} = session_color(event.session_id) %>
            <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{bg}"}></span>
            <span class="text-zinc-600 font-mono w-12 shrink-0 text-right">{relative_time(event.inserted_at, @now)}</span>
            <span :if={event.tool_name} class="text-indigo-400 font-mono shrink-0">{event.tool_name}</span>
            <span class="text-zinc-400 truncate flex-1">{event.summary || event_summary(event)}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
