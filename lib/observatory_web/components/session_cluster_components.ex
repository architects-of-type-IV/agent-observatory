defmodule ObservatoryWeb.Components.SessionClusterComponents do
  use Phoenix.Component

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
    filtered_sessions = filter_sessions(assigns.sessions, assigns.entropy_filter_active, assigns.entropy_threshold)
    assigns = assign(assigns, :filtered_sessions, filtered_sessions)

    ~H"""
    <div id="session-cluster-view" class="p-6 space-y-6">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-semibold text-zinc-300">Session Cluster</h2>
        <button
          phx-click="toggle_entropy_filter"
          class={"px-3 py-1 text-xs rounded-md transition #{if @entropy_filter_active, do: "bg-amber-500/20 text-amber-400 border border-amber-500/30", else: "bg-zinc-800 text-zinc-500 hover:text-zinc-300"}"}
        >
          {if @entropy_filter_active, do: "Entropy Filter: ON", else: "Entropy Filter: OFF"}
        </button>
      </div>

      <%!-- Session List --%>
      <div class="space-y-2">
        <%= if @filtered_sessions == [] do %>
          <p class="empty-state text-sm text-zinc-500 italic">No high-entropy sessions.</p>
        <% else %>
          <div
            :for={session <- @filtered_sessions}
            phx-click="select_session"
            phx-value-session_id={session_id(session)}
            class={"p-3 rounded-lg border cursor-pointer transition #{if @selected_session_id == session_id(session), do: "bg-zinc-800 border-indigo-500/50", else: "bg-zinc-900/50 border-zinc-800 hover:border-zinc-700"}"}
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-mono text-zinc-300">{session_id(session) |> String.slice(0..11)}</span>
              <span class="text-xs text-zinc-500">{Map.get(session, :source_app, "unknown")}</span>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Drill-Down Panel (visible when session selected) --%>
      <div :if={@selected_session_id} class="space-y-4">
        <div id="causal-dag-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Causal DAG</h3>
          <p class="text-xs text-zinc-500">DAG visualization for session {@selected_session_id |> String.slice(0..11)}</p>
        </div>

        <div id="live-scratchpad-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">Live Scratchpad</h3>
          <%= if @scratchpad_intents == [] do %>
            <p class="text-xs text-zinc-500">No intents captured yet</p>
          <% else %>
            <div class="space-y-1">
              <div :for={intent <- @scratchpad_intents} class="text-xs font-mono text-zinc-400">
                {intent}
              </div>
            </div>
          <% end %>
        </div>

        <div id="hitl-console-panel" class="bg-zinc-900/50 border border-zinc-800 rounded-lg p-4">
          <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-2">HITL Console</h3>
          <p class="text-xs text-zinc-500">Human-in-the-loop console placeholder</p>
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
    <div class="bg-zinc-900/50 border border-zinc-800 rounded-lg">
      <button
        phx-click="toggle_subpanel"
        phx-value-panel={@id}
        class="w-full px-4 py-3 flex items-center justify-between text-sm font-semibold text-zinc-400 hover:text-zinc-300 transition"
      >
        <span>{@label}</span>
        <span class="text-xs">{if @open, do: "▼", else: "▶"}</span>
      </button>
      <div :if={@open} class="px-4 pb-4">
        <p class="text-xs text-zinc-500">{@label} sub-panel content placeholder</p>
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
end
