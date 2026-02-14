defmodule ObservatoryWeb.Components.AgentActivity.AgentFocusView do
  @moduledoc """
  Full-screen view of a single agent's activity and metadata.
  """

  use Phoenix.Component
  import ObservatoryWeb.Components.AgentActivity.ActivityStream

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
        <div class="sticky top-0 bg-zinc-950 border-b border-zinc-800 p-3 flex items-center justify-between">
          <h2 class="text-lg font-bold text-zinc-200">
            Activity: {@agent[:name] || "Agent"}
          </h2>
          <button
            phx-click="close_agent_focus"
            class="px-3 py-1 bg-zinc-800 text-zinc-400 rounded text-sm hover:bg-zinc-700 transition"
          >
            Back
          </button>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <.activity_stream
            events={@events}
            expanded_events={@expanded_events}
            limit={999999}
            now={@now}
          />
        </div>
      </div>

      <%!-- Right: Agent metadata sidebar --%>
      <div class="w-80 bg-zinc-900/50 border-l border-zinc-800 overflow-y-auto shrink-0">
        <div class="p-4 space-y-4">
          <div>
            <h3 class="text-xs font-semibold text-zinc-500 uppercase mb-2">Agent Info</h3>
            <div class="space-y-1 text-xs">
              <div class="flex justify-between">
                <span class="text-zinc-500">Name:</span>
                <span class="text-zinc-300">{@agent[:name] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-zinc-500">Type:</span>
                <span class="text-zinc-300">{@agent[:agent_type] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-zinc-500">Model:</span>
                <span class="text-zinc-300">{@agent[:model] || "?"}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-zinc-500">Status:</span>
                <span class={"#{member_status_color(@agent)}"}>
                  {format_status(@agent[:status])}
                </span>
              </div>
              <div :if={@agent[:cwd]} class="flex justify-between">
                <span class="text-zinc-500">CWD:</span>
                <span class="text-zinc-400 font-mono text-[10px] truncate">
                  {@agent[:cwd]}
                </span>
              </div>
              <div :if={@agent[:uptime]} class="flex justify-between">
                <span class="text-zinc-500">Uptime:</span>
                <span class="text-zinc-300">{@agent[:uptime]}</span>
              </div>
              <div :if={@agent[:event_count]} class="flex justify-between">
                <span class="text-zinc-500">Events:</span>
                <span class="text-zinc-300">{@agent[:event_count]}</span>
              </div>
            </div>
          </div>

          <div :if={@tasks != []}>
            <h3 class="text-xs font-semibold text-zinc-500 uppercase mb-2">Assigned Tasks</h3>
            <div class="space-y-1">
              <div
                :for={task <- @tasks}
                class="p-2 bg-zinc-800/50 rounded border border-zinc-800 text-xs"
              >
                <div class="font-semibold text-zinc-300">#{task[:id]}: {task[:subject]}</div>
                <div class="text-zinc-500 mt-1">{task[:status]}</div>
              </div>
            </div>
          </div>

          <div :if={@agent[:health_issues] && @agent[:health_issues] != []}>
            <h3 class="text-xs font-semibold text-zinc-500 uppercase mb-2">Health</h3>
            <div class="space-y-1">
              <div
                :for={issue <- @agent[:health_issues]}
                class="p-2 bg-red-500/10 border border-red-500/30 rounded text-xs text-red-400"
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

  # Import member_status_color from format helpers
  defp member_status_color(member) do
    case member[:status] do
      :active -> "bg-emerald-500"
      :idle -> "bg-amber-500"
      :stopped -> "bg-zinc-600"
      _ -> "bg-zinc-600"
    end
  end
end
