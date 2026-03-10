defmodule IchorWeb.Components.ArchonComponents.CommandHud do
  @moduledoc false

  use Phoenix.Component

  import IchorWeb.Components.ArchonComponents.Icons, only: [hud_icon: 1]
  import IchorWeb.Markdown, only: [render: 1]

  attr :actions, :list, required: true
  attr :loading, :boolean, default: false
  attr :messages, :list, default: []

  def command_hud(assigns) do
    recent =
      assigns.messages
      |> Enum.filter(&(&1.role != :user))
      |> Enum.reverse()
      |> Enum.take(10)
      |> Enum.reverse()

    assigns = assign(assigns, :recent, recent)

    ~H"""
    <div class="flex h-full">
      <%!-- Quick Actions Grid --%>
      <div class="flex-1 p-5 flex flex-col">
        <div class="flex items-center justify-between mb-4">
          <h3 class="archon-section-title">Quick Actions</h3>
          <span class="text-[9px] text-brand/60 font-mono uppercase tracking-widest">
            Press key to execute
          </span>
        </div>
        <div class="grid grid-cols-4 gap-2.5 flex-1 content-start">
          <.action_card :for={action <- @actions} action={action} />
          <%!-- Free-form command slot --%>
          <div class="archon-action-card col-span-1 !border-dashed !border-border">
            <div class="flex items-center justify-between mb-1">
              <span class="archon-action-icon text-muted"><.hud_icon name="command" /></span>
            </div>
            <div id="archon-quick-input" phx-update="ignore">
              <form phx-submit="archon_send" class="flex flex-col gap-1">
                <input
                  type="text"
                  name="content"
                  autocomplete="off"
                  placeholder="Free command..."
                  class="w-full bg-transparent border-0 border-b border-border text-[11px] text-high placeholder-muted p-0 pb-1 focus:outline-none focus:border-brand/50 focus:ring-0"
                />
              </form>
            </div>
          </div>
        </div>
      </div>

      <%!-- Output display --%>
      <div class="archon-output-pane">
        <div class="archon-output-header">
          <%= if @loading do %>
            <span class="archon-output-status-icon archon-output-status-active">
              <svg
                class="w-3.5 h-3.5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              >
                <path d="M12 2L2 7l10 5 10-5-10-5z" />
                <path d="M2 17l10 5 10-5" />
                <path d="M2 12l10 5 10-5" />
              </svg>
            </span>
          <% else %>
            <span class="archon-output-status-icon archon-output-status-idle">
              <svg
                class="w-3.5 h-3.5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="1.5"
              >
                <path d="M4 17l6-6-6-6" /><line x1="12" y1="19" x2="20" y2="19" />
              </svg>
            </span>
          <% end %>
        </div>
        <div class="archon-output-body">
          <%= if @recent == [] do %>
            <div class="archon-output-empty">
              <span class="archon-output-prompt">&gt;_</span>
              <span>Awaiting command</span>
            </div>
          <% else %>
            <.output_entry :for={msg <- @recent} msg={msg} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :action, :map, required: true

  defp action_card(assigns) do
    ~H"""
    <div class="archon-action-card" phx-click="archon_shortcode" phx-value-cmd={@action.cmd}>
      <div class="flex items-center justify-between mb-1.5">
        <span class="archon-action-icon"><.hud_icon name={@action.icon} /></span>
        <kbd class="archon-action-key">{@action.key}</kbd>
      </div>
      <div class="archon-action-label">{@action.label}</div>
      <div class="archon-action-desc">{@action.desc}</div>
    </div>
    """
  end

  # ── Structured output rendering ──────────────────────────────────────

  attr :msg, :map, required: true

  defp output_entry(%{msg: %{type: :agents, data: agents}} = assigns) do
    assigns = assign(assigns, :agents, agents)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Fleet -- {@agents |> length()} agents</div>
      <div class="archon-output-grid">
        <div :for={a <- @agents} class="archon-output-card">
          <div class="flex items-center justify-between">
            <span class="archon-output-card-name">{a["name"]}</span>
            <span class={"archon-output-badge #{status_color(a["status"])}"}>
              {to_string(a["status"] || "unknown")}
            </span>
          </div>
          <div class="archon-output-card-meta">
            <span :if={a["team"]}>{to_string(a["team"])}</span>
            <span :if={a["role"]}>{to_string(a["role"])}</span>
            <span :if={a["current_tool"]} class="archon-output-card-tool">
              {format_tool(a["current_tool"])}
            </span>
          </div>
          <div :if={a["model"]} class="archon-output-card-detail">{a["model"]}</div>
        </div>
      </div>
      <div :if={@agents == []} class="archon-output-empty-result">No active agents</div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :teams, data: teams}} = assigns) do
    assigns = assign(assigns, :teams, teams)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Teams -- {@teams |> length()} active</div>
      <div class="archon-output-grid">
        <div :for={t <- @teams} class="archon-output-card">
          <div class="flex items-center justify-between">
            <span class="archon-output-card-name">{t["name"]}</span>
            <span class={"archon-output-badge #{health_color(t["health"])}"}>
              {to_string(t["health"] || "unknown")}
            </span>
          </div>
          <div class="archon-output-card-meta">
            <span>{t["member_count"] || 0} members</span>
            <span>{to_string(t["source"])}</span>
          </div>
          <div :if={t["members"]} class="archon-output-member-list">
            <div :for={m <- t["members"]} class="archon-output-member">
              <span class="archon-output-member-role">{safe_str(m["role"])}</span>
              <span class="archon-output-member-status">{safe_str(m["status"])}</span>
            </div>
          </div>
        </div>
      </div>
      <div :if={@teams == []} class="archon-output-empty-result">No active teams</div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :health, data: health}} = assigns) do
    assigns = assign(assigns, :health, health)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">System Health</div>
      <div class="archon-output-health-grid">
        <.health_row
          label="Agents"
          value={"#{@health["active_agents"]}/#{@health["agents"]}"}
          ok={@health["active_agents"] > 0}
        />
        <.health_row label="Teams" value={to_string(@health["teams"])} ok={true} />
        <.health_row
          label="EventBuffer"
          value={if @health["event_buffer"], do: "UP", else: "DOWN"}
          ok={@health["event_buffer"]}
        />
        <.health_row
          label="Heartbeat"
          value={if @health["heartbeat"], do: "UP", else: "DOWN"}
          ok={@health["heartbeat"]}
        />
        <.health_row
          label="ProtocolTracker"
          value={if @health["protocol_tracker"], do: "UP", else: "DOWN"}
          ok={@health["protocol_tracker"]}
        />
      </div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :inbox, data: messages}} = assigns) do
    assigns = assign(assigns, :inbox, messages)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Inbox -- {@inbox |> length()} messages</div>
      <div class="archon-output-message-list">
        <div :for={m <- @inbox} class="archon-output-message">
          <div class="flex items-center justify-between">
            <span class="archon-output-card-name">{safe_str(m["from"]) || "system"}</span>
            <span class="archon-output-card-detail">{format_ts(m["timestamp"])}</span>
          </div>
          <div :if={m["to"]} class="archon-output-card-meta">
            <span>to: {safe_str(m["to"])}</span>
          </div>
          <div class="archon-output-message-content">{m["content"]}</div>
        </div>
      </div>
      <div :if={@inbox == []} class="archon-output-empty-result">No messages</div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :sessions, data: sessions}} = assigns) do
    assigns = assign(assigns, :sessions, sessions)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Sessions -- {@sessions |> length()} tmux</div>
      <div class="archon-output-grid">
        <div :for={s <- @sessions} class="archon-output-card">
          <div class="archon-output-card-name font-mono">{s["session"]}</div>
          <div :if={s["agents"] != []} class="archon-output-member-list">
            <div :for={a <- s["agents"]} class="archon-output-member">
              <span class="archon-output-member-role">{a["name"]}</span>
              <span :if={a["team"]} class="archon-output-member-status">{a["team"]}</span>
            </div>
          </div>
          <div :if={s["agents"] == []} class="archon-output-card-meta">
            <span>no agents attached</span>
          </div>
        </div>
      </div>
      <div :if={@sessions == []} class="archon-output-empty-result">No tmux sessions</div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :agent_status, data: %{"found" => false} = d}} = assigns) do
    assigns = assign(assigns, :query, d["query"])

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Agent Status</div>
      <div class="archon-output-empty-result">Agent not found: {@query}</div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :agent_status, data: a}} = assigns) do
    assigns = assign(assigns, :agent, a)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Agent -- {@agent["name"]}</div>
      <div class="archon-output-card" style="margin-top: 0.5rem">
        <div class="flex items-center justify-between mb-2">
          <span class="archon-output-card-name">{@agent["name"]}</span>
          <span class={"archon-output-badge #{status_color(@agent["status"])}"}>
            {to_string(@agent["status"])}
          </span>
        </div>
        <div class="archon-output-detail-grid">
          <.detail_row label="ID" value={to_string(@agent["id"])} />
          <.detail_row
            :if={@agent["session_id"]}
            label="Session"
            value={to_string(@agent["session_id"])}
          />
          <.detail_row :if={@agent["team"]} label="Team" value={to_string(@agent["team"])} />
          <.detail_row :if={@agent["role"]} label="Role" value={to_string(@agent["role"])} />
          <.detail_row :if={@agent["model"]} label="Model" value={to_string(@agent["model"])} />
          <.detail_row
            :if={@agent["current_tool"]}
            label="Tool"
            value={format_tool(@agent["current_tool"])}
          />
          <.detail_row :if={@agent["cwd"]} label="CWD" value={to_string(@agent["cwd"])} />
          <.detail_row
            label="Tmux"
            value={if @agent["tmux_available"], do: @agent["tmux"], else: "disconnected"}
          />
        </div>
      </div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :msg_sent, data: d}} = assigns) do
    assigns = assign(assigns, :result, d)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-label">Message Sent</div>
      <div class={"archon-output-card #{if @result["status"] == "sent", do: "archon-output-card-success", else: "archon-output-card-error"}"}>
        <div class="archon-output-card-name">{@result["status"]}</div>
        <div class="archon-output-card-meta">
          <span>to: {@result["to"]}</span>
          <span :if={@result["delivered"]}>{@result["delivered"]}</span>
        </div>
        <div :if={@result["error"]} class="archon-output-card-detail text-error">
          {@result["error"]}
        </div>
      </div>
    </div>
    """
  end

  defp output_entry(%{msg: %{type: :error, data: data}} = assigns) do
    assigns = assign(assigns, :error, data)

    ~H"""
    <div class="archon-output-section">
      <div class="archon-output-entry text-error">
        <div class="whitespace-pre-wrap">{@error}</div>
      </div>
    </div>
    """
  end

  # Fallback: markdown (LLM responses, remember/recall/query results)
  defp output_entry(%{msg: msg} = assigns) do
    content = msg[:content] || inspect(msg[:data], pretty: true)
    rendered = render(content)
    assigns = assign(assigns, :rendered, rendered)

    ~H"""
    <div class="archon-output-entry">
      <div class="archon-prose">{@rendered}</div>
    </div>
    """
  end

  # ── Sub-components ──────────────────────────────────────────────────

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :ok, :boolean, required: true

  defp health_row(assigns) do
    ~H"""
    <div class="archon-output-health-row">
      <span class="archon-output-health-label">{@label}</span>
      <span class={"archon-output-health-value #{if @ok, do: "archon-health-ok", else: "archon-health-fail"}"}>
        {@value}
      </span>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp detail_row(assigns) do
    ~H"""
    <div class="archon-output-detail-row">
      <span class="archon-output-detail-label">{@label}</span>
      <span class="archon-output-detail-value">{@value}</span>
    </div>
    """
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp status_color(status) when is_atom(status), do: status_color(to_string(status))
  defp status_color("active"), do: "archon-badge-ok"
  defp status_color("paused"), do: "archon-badge-warn"
  defp status_color(_), do: "archon-badge-dim"

  defp health_color("healthy"), do: "archon-badge-ok"
  defp health_color("degraded"), do: "archon-badge-warn"
  defp health_color("critical"), do: "archon-badge-fail"
  defp health_color(_), do: "archon-badge-dim"

  defp format_ts(nil), do: ""

  defp format_ts(%DateTime{} = dt) do
    Calendar.strftime(dt, "%H:%M")
  end

  defp format_ts(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M")
      _ -> ts
    end
  end

  defp format_ts(_), do: ""

  defp format_tool(%{tool_name: name}), do: to_string(name)
  defp format_tool(tool) when is_binary(tool), do: tool
  defp format_tool(tool) when is_atom(tool), do: to_string(tool)
  defp format_tool(tool), do: inspect(tool)

  defp safe_str(nil), do: ""
  defp safe_str(val) when is_binary(val), do: val
  defp safe_str(val) when is_atom(val), do: to_string(val)
  defp safe_str(val), do: inspect(val)
end
