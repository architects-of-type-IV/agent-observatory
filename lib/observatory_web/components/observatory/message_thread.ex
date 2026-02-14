defmodule ObservatoryWeb.Components.Observatory.MessageThread do
  @moduledoc """
  Renders a message thread card with collapsible messages.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardMessageHelpers

  @doc """
  Renders a message thread card with collapsible messages.

  ## Examples

      <.message_thread thread={thread} now={@now} />
  """
  attr :thread, :map, required: true
  attr :now, :any, required: true
  attr :collapsed, :boolean, default: false

  def message_thread(assigns) do
    ~H"""
    <div class="border border-zinc-800 rounded-lg bg-zinc-900/50 overflow-hidden">
      <%!-- Thread header --%>
      <div
        class="px-3 py-2 bg-zinc-800/50 border-b border-zinc-800 flex items-center justify-between cursor-pointer hover:bg-zinc-800/70 transition"
        phx-click="toggle_thread"
        phx-value-key={participant_key(@thread.participants)}
      >
        <div class="flex items-center gap-2 flex-1">
          <span :if={@thread.has_urgent} class="text-red-400 animate-pulse" title="Urgent message">
            ⚠️
          </span>
          <span class="text-xs font-semibold text-zinc-400">
            {format_participants(@thread.participants)}
          </span>
          <span class="text-xs text-zinc-600">{length(@thread.messages)} messages</span>
          <span :if={@thread.unread_count > 0} class="inline-flex items-center justify-center px-1.5 min-w-[1.25rem] h-4 text-xs font-semibold text-white bg-indigo-500 rounded-full">
            {@thread.unread_count}
          </span>
          <%!-- Message type badges --%>
          <div class="flex items-center gap-1">
            <%= for type <- @thread.message_types do %>
              <% {icon, color} = message_type_icon(type) %>
              <span class={"text-xs #{color}"} title={type}>{icon}</span>
            <% end %>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-xs text-zinc-600">{relative_time(@thread.last_message_at, @now)}</span>
          <span class="text-zinc-600 text-xs">{if @collapsed, do: "▶", else: "▼"}</span>
        </div>
      </div>

      <%!-- Thread messages (collapsible) --%>
      <div :if={!@collapsed} class="p-3 space-y-2 max-h-96 overflow-y-auto">
        <div
          :for={msg <- @thread.messages}
          class={"p-2 rounded border transition #{message_border_class(msg.type)}"}
        >
          <div class="flex items-center gap-2 mb-1">
            <% {icon, color} = message_type_icon(msg.type) %>
            <span class={color}>{icon}</span>
            <% {bg, _b, _t} = session_color(msg.sender_session) %>
            <span class={"w-1.5 h-1.5 rounded-full #{bg}"}></span>
            <span class="text-xs font-mono text-zinc-400">{short_session(msg.sender_session)}</span>
            <span class="text-xs text-zinc-700">→</span>
            <span class="text-xs font-mono text-cyan-500">{msg.recipient || "all"}</span>
            <span :if={msg.type != "message"} class={"text-xs px-1 rounded #{message_type_badge_class(msg.type)}"}>
              {msg.type}
            </span>
            <span class="text-xs text-zinc-600 ml-auto" title={format_time(msg.timestamp)}>
              {relative_time(msg.timestamp, @now)}
            </span>
          </div>
          <p class="text-xs text-zinc-300 whitespace-pre-wrap break-words ml-3">{msg.content}</p>
        </div>
      </div>
    </div>
    """
  end
end
