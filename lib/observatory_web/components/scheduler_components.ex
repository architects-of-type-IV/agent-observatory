defmodule ObservatoryWeb.Components.SchedulerComponents do
  use Phoenix.Component

  attr :cron_jobs, :list, default: []
  attr :dlq_entries, :list, default: []
  attr :zombie_agents, :list, default: []

  def scheduler_view(assigns) do
    ~H"""
    <div id="scheduler-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-zinc-300">Scheduler</h2>

      <%!-- Cron Job Dashboard --%>
      <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg">
        <div class="px-4 py-3 border-b border-zinc-800">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Cron Job Dashboard</h3>
        </div>
        <%= if @cron_jobs == [] do %>
          <p class="px-4 py-4 text-sm text-zinc-500">No scheduled jobs</p>
        <% else %>
          <div class="divide-y divide-zinc-800/50">
            <div :for={job <- @cron_jobs} class={"px-4 py-3 flex items-center justify-between cron-status-#{Map.get(job, :state, "pending")}"}>
              <div>
                <span class="text-sm text-zinc-300">{Map.get(job, :name, "unnamed")}</span>
                <div class="text-xs text-zinc-500 mt-0.5">
                  Next: {Map.get(job, :next_run_at, "-")} | Last success: {Map.get(job, :last_success_at, "-")}
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span :if={Map.get(job, :consecutive_failures, 0) > 0} class="text-xs text-red-400">
                  {Map.get(job, :consecutive_failures)} failures
                </span>
                <span class={"px-2 py-0.5 text-xs rounded #{status_class(Map.get(job, :state, "pending"))}"}>
                  {Map.get(job, :state, "pending")}
                </span>
              </div>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Dead Letter Queue --%>
      <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg">
        <div class="px-4 py-3 border-b border-zinc-800">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Dead Letter Queue</h3>
        </div>
        <%= if @dlq_entries == [] do %>
          <p class="empty-state px-4 py-4 text-sm text-zinc-500">No failed deliveries.</p>
        <% else %>
          <div class="divide-y divide-zinc-800/50">
            <div :for={entry <- @dlq_entries} class="px-4 py-3">
              <div class="flex items-center justify-between">
                <div>
                  <span class="text-sm font-mono text-zinc-300">{Map.get(entry, :id, "unknown") |> to_string() |> String.slice(0..11)}</span>
                  <p class="text-xs text-zinc-500 mt-0.5">{Map.get(entry, :failure_reason, "Unknown failure")}</p>
                </div>
                <div class="flex items-center gap-2">
                  <span :if={Map.get(entry, :state) == "pending"} class="text-xs text-amber-400">pending</span>
                  <button
                    :if={Map.get(entry, :state) != "pending"}
                    phx-click="retry_dlq_entry"
                    phx-value-entry_id={Map.get(entry, :id)}
                    class="px-2 py-1 text-xs bg-zinc-700 hover:bg-zinc-600 text-zinc-300 rounded transition"
                  >
                    Retry
                  </button>
                </div>
              </div>
              <p :if={Map.get(entry, :payload)} class="text-xs font-mono text-zinc-600 mt-1 truncate">
                {inspect(Map.get(entry, :payload)) |> String.slice(0..100)}
              </p>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Heartbeat Monitor --%>
      <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg">
        <div class="px-4 py-3 border-b border-zinc-800">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider">Heartbeat Monitor</h3>
        </div>
        <%= if @zombie_agents == [] do %>
          <p class="px-4 py-4 text-sm text-zinc-500">No zombie agents detected</p>
        <% else %>
          <div class="divide-y divide-zinc-800/50">
            <div :for={agent <- @zombie_agents} class="px-4 py-3 flex items-center justify-between">
              <div>
                <span class="text-sm font-mono text-zinc-300">{Map.get(agent, :name, Map.get(agent, :session_id, "unknown"))}</span>
                <span class="text-xs text-red-400 ml-2">zombie</span>
              </div>
              <span class="text-xs text-zinc-500">{Map.get(agent, :last_heartbeat, "-")}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_class("running"), do: "bg-emerald-500/20 text-emerald-400"
  defp status_class("failed"), do: "bg-red-500/20 text-red-400"
  defp status_class(_), do: "bg-zinc-700/50 text-zinc-400"
end
