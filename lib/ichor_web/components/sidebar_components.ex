defmodule IchorWeb.Components.SidebarComponents do
  @moduledoc """
  Right sidebar components: teams, sessions, tmux sessions, message composer.
  """
  use Phoenix.Component

  import IchorWeb.UI, only: [input: 1]
  import IchorWeb.Presentation, only: [member_status_dot_class: 1]

  import IchorWeb.DashboardFormatHelpers,
    only: [session_duration: 2, short_session: 1, session_color: 1]

  import IchorWeb.DashboardSessionHelpers, only: [abbreviate_cwd: 1]

  attr :teams, :list, required: true
  attr :selected_team, :string, default: nil

  def teams_section(assigns) do
    ~H"""
    <div :if={@teams != []} class="mb-3">
      <h2 class="ichor-section-title px-1 mb-1.5">
        Teams <span class="font-mono">({length(@teams)})</span>
      </h2>
      <div class="space-y-1">
        <.team_item :for={team <- @teams} team={team} selected={@selected_team == team.name} />
      </div>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :selected, :boolean, default: false

  defp team_item(assigns) do
    task_total = length(assigns.team.tasks)
    task_done = Enum.count(assigns.team.tasks, fn t -> t[:status] == "completed" end)
    pct = if task_total > 0, do: round(task_done / task_total * 100), else: 0

    assigns =
      assigns
      |> assign(:task_total, task_total)
      |> assign(:task_done, task_done)
      |> assign(:pct, pct)

    ~H"""
    <div
      class={"ichor-sidebar-item #{if @selected, do: "active", else: ""}"}
      phx-click="select_team"
      phx-value-name={@team.name}
    >
      <div class="flex items-center justify-between mb-0.5">
        <span class="si-title font-semibold text-high">{@team.name}</span>
        <span class="si-meta font-mono">{length(@team.members)}</span>
      </div>

      <div :if={@task_total > 0} class="mb-1">
        <div class="flex items-center justify-between si-meta font-mono mb-0.5">
          <span>tasks</span>
          <span>{@task_done}/{@task_total}</span>
        </div>
        <div class="h-1 bg-raised rounded-full overflow-hidden">
          <div class="h-full bg-success rounded-full transition-all" style={"width: #{@pct}%"} />
        </div>
      </div>

      <div class="space-y-0.5">
        <div :for={m <- @team.members} class="flex items-center gap-1.5">
          <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{member_status_dot_class(m[:status])}"} />
          <span class="si-title truncate">{m[:name] || "?"}</span>
          <span :if={m[:agent_type]} class="si-meta ml-auto">{m[:agent_type]}</span>
        </div>
      </div>

      <div class="flex gap-1 mt-1">
        <button
          phx-click="send_team_broadcast"
          phx-value-team={@team.name}
          phx-value-content="status"
          class="flex-1 ichor-btn !text-[9px] !py-0.5 bg-cyan/15 text-cyan hover:bg-cyan/25"
          title={"Ping all agents in #{@team.name}"}
        >
          Ping
        </button>
      </div>
    </div>
    """
  end

  attr :sessions, :list, required: true
  attr :has_teams, :boolean, default: false
  attr :total_sessions, :integer, required: true
  attr :filter_session_id, :string, default: nil
  attr :search_sessions, :string, default: ""
  attr :now, :any, required: true

  def sessions_section(assigns) do
    ~H"""
    <div>
      <div class="flex items-center justify-between mb-1.5 px-1">
        <h2 class="ichor-section-title">
          {if @has_teams, do: "Standalone", else: "Sessions"}
          <span class="font-mono">
            ({length(@sessions)}<span :if={length(@sessions) != @total_sessions}>/{@total_sessions}</span>)
          </span>
        </h2>
      </div>
      <form phx-change="search_sessions" class="mb-1.5 px-0.5">
        <.input
          name="q"
          value={@search_sessions}
          placeholder="Search sessions..."
          autocomplete="off"
          phx-debounce="150"
          class="w-full"
        />
      </form>
      <div class="space-y-0.5">
        <.session_item
          :for={s <- @sessions}
          session={s}
          active={@filter_session_id == s.session_id}
          now={@now}
        />
      </div>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :active, :boolean, default: false
  attr :now, :any, required: true

  defp session_item(assigns) do
    {bg, _border, _text} = session_color(assigns.session.session_id)
    assigns = assign(assigns, :bg, bg)

    ~H"""
    <div
      class={"ichor-sidebar-item #{if @active, do: "active", else: ""}"}
      phx-click="filter_session"
      phx-value-sid={@session.session_id}
    >
      <div class="flex items-center gap-1.5">
        <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{@bg} #{if @session.ended?, do: "opacity-30", else: ""}"} />
        <span class="si-title truncate">{@session.source_app}</span>
        <span class="si-meta font-mono">{short_session(@session.session_id)}</span>
        <IchorWeb.IchorComponents.model_badge model={@session.model} />
      </div>
      <div class="si-meta ml-3 flex items-center gap-1.5 font-mono">
        <span>{@session.event_count}ev</span>
        <span>{session_duration(@session.first_event, @now)}</span>
        <span :if={@session.cwd} class="truncate">{abbreviate_cwd(@session.cwd)}</span>
      </div>
    </div>
    """
  end

  attr :tmux_sessions, :list, required: true
  attr :sessions, :list, required: true

  def tmux_section(assigns) do
    registry_tmux =
      assigns.sessions
      |> Enum.flat_map(fn s ->
        [s.session_id, s[:tmux_session]] |> Enum.reject(&is_nil/1)
      end)
      |> MapSet.new()

    assigns = assign(assigns, :registry_tmux, registry_tmux)

    ~H"""
    <div :if={@tmux_sessions != []} class="mt-3 pt-3 border-t border-border">
      <div class="flex items-center justify-between mb-1.5 px-1">
        <h2 class="ichor-section-title">
          Tmux <span class="font-mono">({length(@tmux_sessions)})</span>
        </h2>
      </div>
      <div class="space-y-0.5">
        <.tmux_item
          :for={name <- @tmux_sessions}
          name={name}
          orphan={!MapSet.member?(@registry_tmux, name)}
        />
      </div>
    </div>
    """
  end

  attr :name, :string, required: true
  attr :orphan, :boolean, default: false

  defp tmux_item(assigns) do
    ~H"""
    <div class="ichor-sidebar-item group">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-1.5 min-w-0">
          <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{if @orphan, do: "bg-warning", else: "bg-success"}"} />
          <span class="si-title truncate font-mono">{@name}</span>
        </div>
        <div class="flex items-center gap-1">
          <span :if={@orphan} class="text-[9px] text-warning font-mono">orphan</span>
          <button
            phx-click="connect_tmux"
            phx-value-session={@name}
            class="opacity-0 group-hover:opacity-100 text-[10px] text-interactive hover:text-high transition px-1"
            title="Open terminal"
          >
            tty
          </button>
          <button
            phx-click="kill_sidebar_tmux"
            phx-value-session={@name}
            class="opacity-0 group-hover:opacity-100 text-[10px] text-error hover:text-high transition px-1"
            title="Kill session"
          >
            kill
          </button>
        </div>
      </div>
    </div>
    """
  end
end
