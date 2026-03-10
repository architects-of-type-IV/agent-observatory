defmodule IchorWeb.Components.FleetCommandComponents do
  use Phoenix.Component
  @moduledoc false

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
      <h2 class="text-lg font-semibold text-high">Fleet Command</h2>

      <%!-- Primary Zone: Mesh Topology Map --%>
      <div
        id="fleet-topology-hook"
        phx-hook="TopologyMap"
        data-event="fleet_topology_update"
        class="bg-base/50 border border-border rounded-lg p-4 min-h-[300px]"
      >
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
          Mesh Topology
        </h3>
        <canvas width="800" height="280" class="w-full rounded"></canvas>
      </div>

      <%!-- Secondary Zone: Five Panels --%>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div id="throughput-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">Throughput</h3>
          <%= if @throughput_rate do %>
            <div class="flex items-baseline gap-1">
              <span class="text-2xl font-mono font-bold text-high">{@throughput_rate}</span>
              <span class="text-xs text-low">events/sec</span>
            </div>
          <% else %>
            <p class="text-sm text-low">Waiting for events...</p>
          <% end %>
        </div>

        <div id="cost-heatmap-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
            Cost Heatmap
          </h3>
          <%= if @cost_heatmap == [] do %>
            <p class="text-sm text-low">No cost data available</p>
          <% else %>
            <div class="space-y-1">
              <div :for={entry <- @cost_heatmap} class="flex justify-between text-xs">
                <span class="text-default font-mono">
                  {Map.get(entry, :agent_id, "unknown") |> String.slice(0..7)}
                </span>
                <span class="text-high">${Map.get(entry, :cost, 0.0) |> Float.round(4)}</span>
              </div>
            </div>
          <% end %>
        </div>

        <div id="infrastructure-health-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
            Infrastructure Health
          </h3>
          <%= cond do %>
            <% is_map(@node_status) and map_size(@node_status) > 0 -> %>
              <div class="space-y-1">
                <div class="flex items-center gap-2">
                  <span class={"w-2 h-2 rounded-full #{node_state_color(Map.get(@node_status, :state))}"}>
                  </span>
                  <span class="text-sm text-high">
                    {Map.get(@node_status, :agent_id) ||
                      Map.get(@node_status, :session_id, "unknown")
                      |> to_string()
                      |> String.slice(0..11)}
                  </span>
                  <span class="text-xs text-low">{Map.get(@node_status, :state, "unknown")}</span>
                </div>
              </div>
            <% true -> %>
              <p class="text-sm text-low">All nodes healthy</p>
          <% end %>
        </div>

        <div id="latency-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">Latency</h3>
          <%= if @latency_metrics == %{} do %>
            <p class="text-sm text-low">Loading...</p>
          <% else %>
            <div class="grid grid-cols-3 gap-2 text-center">
              <div>
                <div class="text-xs text-low">p50</div>
                <div class="text-sm font-mono text-high">
                  {Map.get(@latency_metrics, :p50, "-")}ms
                </div>
              </div>
              <div>
                <div class="text-xs text-low">p95</div>
                <div class="text-sm font-mono text-high">
                  {Map.get(@latency_metrics, :p95, "-")}ms
                </div>
              </div>
              <div>
                <div class="text-xs text-low">p99</div>
                <div class="text-sm font-mono text-high">
                  {Map.get(@latency_metrics, :p99, "-")}ms
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div id="mtls-status-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
            mTLS Status
          </h3>
          <p class="text-sm text-low">{@mtls_status || "Not configured"}</p>
        </div>
      </div>

      <%!-- Collapsible Agent Grid --%>
      <div class="bg-base/50 border border-border rounded-lg">
        <button
          phx-click="toggle_agent_grid"
          class="w-full px-4 py-3 flex items-center justify-between text-sm font-semibold text-default hover:text-high transition"
        >
          <span>Agent Grid</span>
          <span class="text-xs">{if @agent_grid_open, do: "▼", else: "▶"}</span>
        </button>
        <div :if={@agent_grid_open} id="agent-grid-panel" class="px-4 pb-4">
          <p class="text-xs text-low">Agent grid sub-panel placeholder</p>
        </div>
      </div>
    </div>
    """
  end

  defp node_state_color(:schema_violation), do: "bg-error"
  defp node_state_color("alert_entropy"), do: "bg-brand"
  defp node_state_color("blocked"), do: "bg-yellow-500"
  defp node_state_color("active"), do: "bg-success"
  defp node_state_color(_), do: "bg-low"
end
