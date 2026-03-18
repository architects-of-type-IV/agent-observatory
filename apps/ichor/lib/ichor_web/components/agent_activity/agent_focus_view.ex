defmodule IchorWeb.Components.AgentActivity.AgentFocusView do
  @moduledoc """
  Full-screen view of a single agent's activity and metadata.
  """

  use Phoenix.Component
  import IchorWeb.Components.AgentActivity.ActivityStream
  import IchorWeb.DashboardTeamHelpers, only: [member_status_color: 1]

  attr :agent, :map, required: true
  attr :events, :list, required: true
  attr :tasks, :list, required: true
  attr :expanded_events, :list, default: []
  attr :now, :any, required: true

  def agent_focus_view(assigns) do
    ~H"""
    <div class="flex h-full gap-4">
      <%!-- Left: Activity stream (scrollable) --%>
      <div class="flex-1 flex flex-col min-w-0">
        <div class="sticky top-0 bg-base border-b border-border p-3 flex items-center justify-between">
          <h2 class="text-lg font-bold text-high">
            Activity: {@agent[:name] || "Agent"}
          </h2>
          <button
            phx-click="close_agent_focus"
            class="px-3 py-1 bg-raised text-default rounded text-sm hover:bg-highlight transition"
          >
            Back
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <.activity_stream
            events={@events}
            expanded_events={@expanded_events}
            limit={999_999}
            now={@now}
          />
        </div>
      </div>

      <%!-- Right: Agent metadata sidebar --%>
      <div class="w-80 bg-base/50 border-l border-border overflow-y-auto shrink-0">
        <div class="p-4 space-y-4">
          <div>
            <h3 class="text-xs font-semibold text-low uppercase mb-2">Agent Info</h3>
            <div class="space-y-1 text-xs">
              <div class="flex justify-between">
                <span class="text-low">Name:</span>
                <span class="text-high">{@agent[:name] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-low">Type:</span>
                <span class="text-high">{@agent[:agent_type] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-low">Model:</span>
                <span class="text-high">{@agent[:model] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-low">Status:</span>
                <span class={"#{member_status_color(@agent)}"}>
                  {format_status(@agent[:status])}
                </span>
              </div>
              <div :if={@agent[:cwd]} class="flex justify-between">
                <span class="text-low">CWD:</span>
                <span class="text-default font-mono text-[10px] truncate">
                  {@agent[:cwd]}
                </span>
              </div>
              <div :if={@agent[:uptime]} class="flex justify-between">
                <span class="text-low">Uptime:</span>
                <span class="text-high">{@agent[:uptime]}</span>
              </div>
              <div :if={@agent[:event_count]} class="flex justify-between">
                <span class="text-low">Events:</span>
                <span class="text-high">{@agent[:event_count]}</span>
              </div>
            </div>
          </div>

          <div :if={@tasks != []}>
            <h3 class="text-xs font-semibold text-low uppercase mb-2">Assigned Tasks</h3>
            <div class="space-y-1">
              <div
                :for={task <- @tasks}
                class="p-2 bg-raised/50 rounded border border-border text-xs"
              >
                <div class="font-semibold text-high">#{task[:id]}: {task[:subject]}</div>
                <div class="text-low mt-1">{task[:status]}</div>
              </div>
            </div>
          </div>

          <div :if={@agent[:health_issues] && @agent[:health_issues] != []}>
            <h3 class="text-xs font-semibold text-low uppercase mb-2">Health</h3>
            <div class="space-y-1">
              <div
                :for={issue <- @agent[:health_issues]}
                class="p-2 bg-error/10 border border-error/30 rounded text-xs text-error"
              >
                {issue}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper for status display
  defp format_status(:active), do: "Active"
  defp format_status(:idle), do: "Idle"
  defp format_status(:stopped), do: "Stopped"
  defp format_status(_), do: "Unknown"
end
