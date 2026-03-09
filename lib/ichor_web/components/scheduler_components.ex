defmodule IchorWeb.Components.SchedulerComponents do
  use Phoenix.Component

  attr :cron_jobs, :list, default: []
  attr :dlq_entries, :list, default: []
  attr :zombie_agents, :list, default: []

  def scheduler_view(assigns) do
    ~H"""
    <div id="scheduler-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-high">Scheduler</h2>

      <%!-- Cron Job Dashboard --%>
      <div class="bg-base/50 border border-border rounded-lg">
        <div class="px-4 py-3 border-b border-border">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider">Cron Job Dashboard</h3>
        </div>
        <%= if @cron_jobs == [] do %>
          <p class="px-4 py-4 text-sm text-low">No scheduled jobs</p>
        <% else %>
          <div class="divide-y divide-border/50">
            <div :for={job <- @cron_jobs} class={"px-4 py-3 flex items-center justify-between cron-status-#{Map.get(job, :state, "pending")}"}>
              <div>
                <span class="text-sm text-high">{Map.get(job, :name, "unnamed")}</span>
                <div class="text-xs text-low mt-0.5">
                  Next: {Map.get(job, :next_run_at, "-")} | Last success: {Map.get(job, :last_success_at, "-")}
                </div>
              </div>
              <div class="flex items-center gap-2">
                <span :if={Map.get(job, :consecutive_failures, 0) > 0} class="text-xs text-error">
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
      <div class="bg-base/50 border border-border rounded-lg">
        <div class="px-4 py-3 border-b border-border">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider">Dead Letter Queue</h3>
        </div>
        <%= if @dlq_entries == [] do %>
          <p class="empty-state px-4 py-4 text-sm text-low">No failed deliveries.</p>
        <% else %>
          <div class="divide-y divide-border/50">
            <div :for={entry <- @dlq_entries} class="px-4 py-3">
              <div class="flex items-center justify-between">
                <div>
                  <span class="text-sm font-mono text-high">{Map.get(entry, :id, "unknown") |> to_string() |> String.slice(0..11)}</span>
                  <p class="text-xs text-low mt-0.5">{Map.get(entry, :failure_reason, "Unknown failure")}</p>
                </div>
                <div class="flex items-center gap-2">
                  <span :if={Map.get(entry, :state) == "pending"} class="text-xs text-brand">pending</span>
                  <button
                    :if={Map.get(entry, :state) != "pending"}
                    phx-click="retry_dlq_entry"
                    phx-value-entry_id={Map.get(entry, :id)}
                    class="px-2 py-1 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                  >
                    Retry
                  </button>
                </div>
              </div>
              <p :if={Map.get(entry, :payload)} class="text-xs font-mono text-muted mt-1 truncate">
                {inspect(Map.get(entry, :payload)) |> String.slice(0..100)}
              </p>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Heartbeat Monitor --%>
      <div class="bg-base/50 border border-border rounded-lg">
        <div class="px-4 py-3 border-b border-border">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider">Heartbeat Monitor</h3>
        </div>
        <%= if @zombie_agents == [] do %>
          <p class="px-4 py-4 text-sm text-low">No zombie agents detected</p>
        <% else %>
          <div class="divide-y divide-border/50">
            <div :for={agent <- @zombie_agents} class="px-4 py-3 flex items-center justify-between">
              <div>
                <span class="text-sm font-mono text-high">{Map.get(agent, :name, Map.get(agent, :session_id, "unknown"))}</span>
                <span class="text-xs text-error ml-2">zombie</span>
              </div>
              <span class="text-xs text-low">{Map.get(agent, :last_heartbeat, "-")}</span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp status_class("running"), do: "bg-success/20 text-success"
  defp status_class("failed"), do: "bg-error/20 text-error"
  defp status_class(_), do: "bg-highlight/50 text-default"
end
