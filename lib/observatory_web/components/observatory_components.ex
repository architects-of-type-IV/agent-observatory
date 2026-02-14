defmodule ObservatoryWeb.ObservatoryComponents do
  @moduledoc """
  Reusable function components for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardTeamHelpers
  import ObservatoryWeb.DashboardSessionHelpers
  import ObservatoryWeb.DashboardAgentHealthHelpers
  import ObservatoryWeb.DashboardMessageHelpers

  @doc """
  Renders a session color dot.

  ## Examples

      <.session_dot session_id={event.session_id} />
      <.session_dot session_id={event.session_id} ended={true} />
  """
  attr :session_id, :string, required: true
  attr :ended, :boolean, default: false
  attr :size, :string, default: "w-2 h-2"

  def session_dot(assigns) do
    assigns = assign(assigns, :color_classes, session_color(assigns.session_id))

    ~H"""
    <% {bg, _border, _text} = @color_classes %>
    <span class={"#{@size} rounded-full shrink-0 #{bg} #{if @ended, do: "opacity-30", else: ""}"}></span>
    """
  end

  @doc """
  Renders an event type badge.

  ## Examples

      <.event_type_badge type={event.hook_event_type} />
  """
  attr :type, :atom, required: true

  def event_type_badge(assigns) do
    assigns = assign(assigns, :badge_info, event_type_label(assigns.type))

    ~H"""
    <% {label, badge_class} = @badge_info %>
    <span class={"text-xs font-mono px-1.5 py-0 rounded shrink-0 #{badge_class}"}>
      {label}
    </span>
    """
  end

  @doc """
  Renders a status dot for team members.

  ## Examples

      <.member_status_dot status={:active} />
      <.member_status_dot status={:idle} />
  """
  attr :status, :atom, required: true

  def member_status_dot(assigns) do
    ~H"""
    <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{member_status_color(@status)}"}></span>
    """
  end

  @doc """
  Renders an empty state with icon and guidance text.

  ## Examples

      <.empty_state
        title="No tasks yet"
        description="Tasks will appear when agents use TaskCreate/TaskUpdate"
      />
  """
  attr :title, :string, required: true
  attr :description, :string, required: true

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-24 text-zinc-600">
      <p class="text-lg">{@title}</p>
      <p class="text-sm mt-1 text-zinc-700">{@description}</p>
    </div>
    """
  end

  @doc """
  Renders health warnings for an agent.

  ## Examples

      <.health_warnings issues={member[:health_issues]} />
  """
  attr :issues, :list, required: true

  def health_warnings(assigns) do
    ~H"""
    <div :if={@issues != []} class="mt-2 ml-4 space-y-0.5">
      <div :for={issue <- @issues} class="text-xs text-red-400/80">
        {format_issue(issue)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a model badge.

  ## Examples

      <.model_badge model="opus" />
  """
  attr :model, :string, default: nil

  def model_badge(assigns) do
    ~H"""
    <span :if={@model} class="text-xs font-mono px-1.5 py-0.5 rounded bg-indigo-500/15 text-indigo-400 border border-indigo-500/30">
      {short_model_name(@model)}
    </span>
    """
  end

  @doc """
  Renders a toast notification container.

  ## Examples

      <.toast_container />
  """
  def toast_container(assigns) do
    ~H"""
    <div
      id="toast-container"
      phx-hook="Toast"
      class="fixed top-4 right-4 z-50 flex flex-col gap-2 pointer-events-none"
    >
    </div>
    """
  end

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
