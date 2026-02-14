defmodule ObservatoryWeb.ObservatoryComponents do
  @moduledoc """
  Reusable function components for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardTeamHelpers

  @doc """
  Renders a task board column with filtered tasks.

  ## Examples

      <.task_column
        status="pending"
        title="Pending"
        tasks={@active_tasks}
        dot_class="bg-zinc-500"
        title_class="text-zinc-400"
        card_border="border-zinc-800 hover:border-zinc-700"
        owner_class="text-zinc-500"
      />
  """
  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :tasks, :list, required: true
  attr :dot_class, :string, default: "bg-zinc-500"
  attr :title_class, :string, default: "text-zinc-400"
  attr :card_border, :string, default: "border-zinc-800 hover:border-zinc-700"
  attr :owner_class, :string, default: "text-zinc-500"
  attr :subject_class, :string, default: "text-zinc-300"
  attr :show_active_form, :boolean, default: false
  attr :show_blocked_by, :boolean, default: false
  attr :animate_dot, :boolean, default: false

  def task_column(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 mb-3 px-1">
        <span class={"w-2 h-2 rounded-full #{@dot_class} #{if @animate_dot, do: "animate-pulse", else: ""}"}></span>
        <h3 class={"text-xs font-semibold #{@title_class} uppercase tracking-wider"}>{@title}</h3>
        <span class="text-xs text-zinc-600">
          ({length(Enum.filter(@tasks, fn t -> t[:status] == @status end))})
        </span>
      </div>
      <div class="space-y-2">
        <div
          :for={task <- Enum.filter(@tasks, fn t -> t[:status] == @status end)}
          class={"p-3 rounded-lg bg-zinc-900 border #{@card_border} transition cursor-pointer"}
          phx-click="select_task"
          phx-value-id={task[:id]}
        >
          <div class="flex items-center justify-between mb-1">
            <span class="text-xs font-mono text-zinc-600">#{task[:id]}</span>
            <span :if={task[:owner]} class={"text-xs #{@owner_class}"}>@{task[:owner]}</span>
          </div>
          <p class={"text-sm #{@subject_class}"}>{task[:subject]}</p>
          <p :if={@show_active_form && task[:active_form]} class="text-xs text-blue-400/60 mt-1">
            {task[:active_form]}
          </p>
          <div :if={@show_blocked_by && task[:blocked_by] && task[:blocked_by] != []} class="mt-1.5">
            <span class="text-xs text-amber-500/70">blocked by #{Enum.join(task[:blocked_by], ", #")}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

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
end
