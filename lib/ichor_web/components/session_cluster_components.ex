defmodule IchorWeb.Components.SessionClusterComponents do
  use Phoenix.Component
  @moduledoc false

  attr :sessions, :list, default: []
  attr :entropy_filter_active, :boolean, default: false
  attr :entropy_threshold, :float, default: 0.7
  attr :selected_session_id, :any, default: nil
  attr :scratchpad_intents, :list, default: []
  attr :feed_panel_open, :boolean, default: false
  attr :messages_panel_open, :boolean, default: false
  attr :tasks_panel_open, :boolean, default: false
  attr :protocols_panel_open, :boolean, default: false

  def session_cluster_view(assigns) do
    filtered_sessions =
      filter_sessions(assigns.sessions, assigns.entropy_filter_active, assigns.entropy_threshold)

    assigns = assign(assigns, :filtered_sessions, filtered_sessions)

    ~H"""
    <div id="session-cluster-view" class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold text-high">Session Cluster</h2>
        <button
          phx-click="toggle_entropy_filter"
          class={"px-3 py-1 text-xs rounded-md transition #{if @entropy_filter_active, do: "bg-brand/20 text-brand border border-brand/30", else: "bg-raised text-low hover:text-high"}"}
        >
          {if @entropy_filter_active, do: "Entropy Filter: ON", else: "Entropy Filter: OFF"}
        </button>
      </div>

      <%!-- Session List --%>
      <div class="space-y-2">
        <%= if @filtered_sessions == [] do %>
          <p class="empty-state text-sm text-low italic">No high-entropy sessions.</p>
        <% else %>
          <div
            :for={session <- @filtered_sessions}
            phx-click="select_session"
            phx-value-session_id={session_id(session)}
            class={"p-3 rounded-lg border cursor-pointer transition #{if @selected_session_id == session_id(session), do: "bg-raised border-interactive/50", else: "bg-base/50 border-border hover:border-border-subtle"}"}
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-mono text-high">
                {session_id(session) |> String.slice(0..11)}
              </span>
              <span class="text-xs text-low">{Map.get(session, :source_app, "unknown")}</span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Drill-Down Panel (visible when session selected) --%>
      <div :if={@selected_session_id} class="space-y-4">
        <div
          id="session-dag-hook"
          phx-hook="TopologyMap"
          phx-update="ignore"
          data-event="session_dag_update"
          class="bg-base/30 border border-border rounded-lg p-4 min-h-[120px] relative"
        >
          <h3 class="topo-title text-[10px] font-semibold text-muted uppercase tracking-wider mb-2">
            Causal DAG: {@selected_session_id |> String.slice(0..11)}
          </h3>
        </div>

        <div id="live-scratchpad-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
            Live Scratchpad
          </h3>
          <%= if @scratchpad_intents == [] do %>
            <p class="text-xs text-low">No intents captured yet</p>
          <% else %>
            <div class="space-y-1.5 max-h-64 overflow-y-auto">
              <div
                :for={intent <- Enum.take(@scratchpad_intents, 50)}
                class="flex items-center gap-2 text-xs"
              >
                <span class="font-mono text-interactive">{format_intent(intent)}</span>
                <span :if={format_confidence(intent)} class="text-muted">
                  {format_confidence(intent)}
                </span>
                <span :if={format_strategy(intent)} class="text-muted italic">
                  {format_strategy(intent)}
                </span>
              </div>
            </div>
          <% end %>
        </div>

        <div id="hitl-console-panel" class="bg-base/50 border border-border rounded-lg p-4">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-2">
            HITL Console
          </h3>
          <p class="text-xs text-low">Human-in-the-loop console placeholder</p>
        </div>

        <%!-- Collapsible Sub-Panels --%>
        <.collapsible_panel id="feed" label="Feed" open={@feed_panel_open} />
        <.collapsible_panel id="messages" label="Messages" open={@messages_panel_open} />
        <.collapsible_panel id="tasks" label="Tasks" open={@tasks_panel_open} />
        <.collapsible_panel id="protocols" label="Protocols" open={@protocols_panel_open} />
      </div>
    </div>
    """
  end

  defp collapsible_panel(assigns) do
    ~H"""
    <div class="bg-base/50 border border-border rounded-lg">
      <button
        phx-click="toggle_subpanel"
        phx-value-panel={@id}
        class="w-full px-4 py-3 flex items-center justify-between text-sm font-semibold text-default hover:text-high transition"
      >
        <span>{@label}</span>
        <span class="text-xs">{if @open, do: "▼", else: "▶"}</span>
      </button>
      <div :if={@open} class="px-4 pb-4">
        <p class="text-xs text-low">{@label} sub-panel content placeholder</p>
      </div>
    </div>
    """
  end

  defp filter_sessions(sessions, false, _threshold), do: sessions

  defp filter_sessions(sessions, true, threshold) do
    Enum.filter(sessions, fn s ->
      Map.get(s, :entropy_score, 0.0) > threshold
    end)
  end

  defp session_id(session) when is_map(session),
    do: Map.get(session, :session_id, Map.get(session, "session_id", "unknown"))

  defp session_id(_), do: "unknown"

  defp format_intent(%{intent: intent}) when is_binary(intent), do: intent
  defp format_intent(_), do: "unknown"

  defp format_confidence(%{confidence: c}) when is_number(c), do: "#{Float.round(c * 1.0, 2)}"
  defp format_confidence(_), do: nil

  defp format_strategy(%{strategy: s}) when is_binary(s), do: s
  defp format_strategy(_), do: nil
end
