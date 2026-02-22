defmodule ObservatoryWeb.Components.FleetCommandComponents do
  use Phoenix.Component

  attr :swarm_state, :map, default: %{}
  attr :throughput_rate, :any, default: nil
  attr :cost_heatmap, :list, default: []
  attr :node_status, :any, default: nil
  attr :latency_metrics, :map, default: %{}
  attr :mtls_status, :any, default: nil
  attr :agent_grid_open, :boolean, default: false
  attr :teams, :list, default: []
  attr :events, :list, default: []
  attr :errors, :list, default: []
  attr :now, :any, default: nil
  attr :selected_command_agent, :any, default: nil
  attr :selected_command_task, :any, default: nil
  attr :messages, :list, default: []
  attr :protocol_stats, :map, default: %{}
  attr :active_tasks, :list, default: []
  attr :analytics, :map, default: %{}

  def fleet_command_view(assigns) do
    ~H"""
    <div id="fleet-command-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-zinc-300">Fleet Command</h2>

      <%!-- Primary Zone: Mesh Topology Map --%>
      <div id="mesh-topology-canvas" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4 min-h-[300px]">
        <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Mesh Topology</h3>
        <p class="text-xs text-zinc-600">Topology map canvas placeholder</p>
      </div>

      <%!-- Secondary Zone: Five Panels --%>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div id="throughput-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Throughput</h3>
          <p class="text-sm text-zinc-300">{@throughput_rate || "Loading..."}</p>
        </div>

        <div id="cost-heatmap-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Cost Heatmap</h3>
          <%= if @cost_heatmap == [] do %>
            <p class="text-sm text-zinc-500">No cost data available</p>
          <% else %>
            <div class="space-y-1">
              <div :for={entry <- @cost_heatmap} class="flex justify-between text-xs">
                <span class="text-zinc-400 font-mono">{Map.get(entry, :agent_id, "unknown") |> String.slice(0..7)}</span>
                <span class="text-zinc-300">${Map.get(entry, :cost, 0.0) |> Float.round(4)}</span>
              </div>
            </div>
          <% end %>
        </div>

        <div id="infrastructure-health-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Infrastructure Health</h3>
          <p class="text-sm text-zinc-300">{@node_status || "Loading..."}</p>
        </div>

        <div id="latency-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Latency</h3>
          <%= if @latency_metrics == %{} do %>
            <p class="text-sm text-zinc-500">Loading...</p>
          <% else %>
            <div class="grid grid-cols-3 gap-2 text-center">
              <div>
                <div class="text-xs text-zinc-500">p50</div>
                <div class="text-sm font-mono text-zinc-300">{Map.get(@latency_metrics, :p50, "-")}ms</div>
              </div>
              <div>
                <div class="text-xs text-zinc-500">p95</div>
                <div class="text-sm font-mono text-zinc-300">{Map.get(@latency_metrics, :p95, "-")}ms</div>
              </div>
              <div>
                <div class="text-xs text-zinc-500">p99</div>
                <div class="text-sm font-mono text-zinc-300">{Map.get(@latency_metrics, :p99, "-")}ms</div>
              </div>
            </div>
          <% end %>
        </div>

        <div id="mtls-status-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">mTLS Status</h3>
          <p class="text-sm text-zinc-300">{@mtls_status || "Loading..."}</p>
        </div>
      </div>

      <%!-- Collapsible Agent Grid --%>
      <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg">
        <button
          phx-click="toggle_agent_grid"
          class="w-full px-4 py-3 flex items-center justify-between text-sm font-semibold text-zinc-400 hover:text-zinc-300 transition"
        >
          <span>Agent Grid</span>
          <span class="text-xs">{if @agent_grid_open, do: "▼", else: "▶"}</span>
        </button>
        <div :if={@agent_grid_open} id="agent-grid-panel" class="px-4 pb-4">
          <p class="text-xs text-zinc-500">Agent grid sub-panel placeholder</p>
        </div>
      </div>
    </div>
    """
  end
end
