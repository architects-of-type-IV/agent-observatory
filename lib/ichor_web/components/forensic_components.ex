defmodule IchorWeb.Components.ForensicComponents do
  use Phoenix.Component

  attr :archive_search, :string, default: ""
  attr :archive_results, :list, default: []
  attr :cost_group_by, :atom, default: :agent_id
  attr :cost_attribution, :list, default: []
  attr :webhook_logs, :list, default: []
  attr :policy_rules, :list, default: []
  attr :forensic_audit_open, :boolean, default: false
  attr :forensic_topology_open, :boolean, default: false
  attr :forensic_entropy_open, :boolean, default: false

  def forensic_view(assigns) do
    ~H"""
    <div id="forensic-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-high">Forensic Inspector</h2>

      <%!-- Message Archive --%>
      <div id="message-archive-panel" class="bg-base/50 border border-border rounded-lg p-4">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-3">
          Message Archive
        </h3>
        <form phx-change="search_archive" class="mb-3">
          <input
            type="text"
            name="q"
            value={@archive_search}
            placeholder="Search archived messages..."
            autocomplete="off"
            phx-debounce="200"
            class="w-full bg-raised border border-border-subtle rounded px-2.5 py-1 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0 focus:outline-none"
          />
        </form>
        <%= if @archive_search != "" and @archive_results == [] do %>
          <p class="empty-state text-sm text-low italic">No matching messages found.</p>
        <% else %>
          <div :if={@archive_results != []} class="space-y-1 max-h-48 overflow-y-auto">
            <div
              :for={result <- Enum.take(@archive_results, 50)}
              class="text-xs font-mono text-default truncate"
            >
              {inspect(result) |> String.slice(0..120)}
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Cost Attribution --%>
      <div id="cost-attribution-panel" class="bg-base/50 border border-border rounded-lg p-4">
        <div class="flex items-center justify-between mb-3">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider">
            Cost Attribution
          </h3>
          <div class="flex items-center gap-1">
            <span class="text-xs text-low">Group by:</span>
            <button
              :for={field <- [:agent_id, :session_id, :team]}
              phx-click="set_cost_group_by"
              phx-value-field={field}
              class={"px-2 py-0.5 text-xs rounded transition #{if @cost_group_by == field, do: "bg-highlight text-high", else: "text-low hover:text-high"}"}
            >
              {field}
            </button>
          </div>
        </div>
        <%= if @cost_attribution == [] do %>
          <p class="text-sm text-low">No cost data available</p>
        <% else %>
          <div class="space-y-1">
            <div :for={entry <- @cost_attribution} class="flex justify-between text-xs">
              <span class="text-default">{Map.get(entry, @cost_group_by, "unknown")}</span>
              <span class="text-high font-mono">${Map.get(entry, :cost, 0.0)}</span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Security Panel --%>
      <div id="security-panel" class="bg-base/50 border border-border rounded-lg p-4">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-3">
          Security Webhook Log
        </h3>
        <%= if @webhook_logs == [] do %>
          <p class="text-sm text-low">No webhook events recorded</p>
        <% else %>
          <div class="space-y-1 max-h-48 overflow-y-auto">
            <div :for={log <- Enum.take(@webhook_logs, 50)} class="text-xs font-mono text-default">
              <span class="text-low">{Map.get(log, :timestamp, "-")}</span>
              <span class="ml-2">{Map.get(log, :status, "-")}</span>
              <span class="ml-2 text-muted">{Map.get(log, :url, "-")}</span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Policy Engine --%>
      <div id="policy-engine-panel" class="bg-base/50 border border-border rounded-lg p-4">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-3">
          Policy Engine
        </h3>
        <%= if @policy_rules == [] do %>
          <p class="text-sm text-low mb-3">No policy rules configured</p>
        <% else %>
          <div class="space-y-2 mb-3">
            <div
              :for={rule <- @policy_rules}
              class="flex items-center justify-between bg-raised/50 rounded px-3 py-2"
            >
              <div>
                <span class="text-sm text-high">{Map.get(rule, :name, "unnamed")}</span>
                <span class="text-xs text-low ml-2">{Map.get(rule, :condition, "")}</span>
              </div>
              <span class={"text-xs #{if Map.get(rule, :enabled, false), do: "text-success", else: "text-muted"}"}>
                {if Map.get(rule, :enabled, false), do: "active", else: "disabled"}
              </span>
            </div>
          </div>
        <% end %>
        <form phx-submit="add_policy_rule" class="flex items-center gap-2">
          <input
            type="text"
            name="name"
            placeholder="Rule name"
            class="flex-1 bg-raised border border-border-subtle rounded px-2 py-1 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0"
          />
          <input
            type="text"
            name="condition"
            placeholder="Condition"
            class="flex-1 bg-raised border border-border-subtle rounded px-2 py-1 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0"
          />
          <input
            type="text"
            name="action"
            placeholder="Action"
            class="flex-1 bg-raised border border-border-subtle rounded px-2 py-1 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0"
          />
          <button
            type="submit"
            class="px-3 py-1 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
          >
            Add
          </button>
        </form>
      </div>

      <%!-- Collapsible Sub-Panels --%>
      <.forensic_subpanel id="audit" label="Audit Trail" open={@forensic_audit_open} />
      <.forensic_subpanel id="topology" label="Topology Snapshot" open={@forensic_topology_open} />
      <.forensic_subpanel id="entropy" label="Entropy History" open={@forensic_entropy_open} />
    </div>
    """
  end

  defp forensic_subpanel(assigns) do
    ~H"""
    <div class="bg-base/50 border border-border rounded-lg">
      <button
        phx-click="toggle_forensic_panel"
        phx-value-panel={@id}
        class="w-full px-4 py-3 flex items-center justify-between text-sm font-semibold text-default hover:text-high transition"
      >
        <span>{@label}</span>
        <span class="text-xs">{if @open, do: "▼", else: "▶"}</span>
      </button>
      <div :if={@open} class="px-4 pb-4">
        <p class="text-xs text-low">{@label} content placeholder</p>
      </div>
    </div>
    """
  end
end
