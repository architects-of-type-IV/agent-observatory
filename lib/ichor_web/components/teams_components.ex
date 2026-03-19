defmodule IchorWeb.Components.TeamsComponents do
  @moduledoc """
  Teams view component for the Ichor dashboard.
  """

  use Phoenix.Component
  import IchorWeb.IchorComponents
  import IchorWeb.DashboardTeamHelpers
  import IchorWeb.Presentation, only: [health_bg_class: 1]

  attr :teams, :list, required: true
  attr :inspected_teams, :list, default: []
  attr :now, :any, required: true

  def teams_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center gap-3">
        <h2 class="text-lg font-medium text-high">Teams</h2>
        <span class="px-2 py-0.5 text-xs font-medium bg-raised text-default rounded">
          {length(@teams)}
        </span>
      </div>

      <%= if @teams == [] do %>
        <.empty_state
          title="No teams yet"
          description="Teams will appear when agents use TeamCreate"
        />
      <% else %>
        <div class="grid gap-3">
          <%= for team <- @teams do %>
            <.team_row
              team={team}
              inspected={team.name in @inspected_teams}
              now={@now}
            />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  attr :team, :map, required: true
  attr :inspected, :boolean, required: true
  attr :now, :any, required: true

  defp team_row(assigns) do
    summary = team_summary(assigns.team)
    {completed, total} = summary.progress

    assigns =
      assigns
      |> assign(:summary, summary)
      |> assign(:completed, completed)
      |> assign(:total, total)

    ~H"""
    <div class={[
      "p-4 rounded-lg border bg-base/50",
      (@inspected && "border-interactive/40") || "border-border"
    ]}>
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-3 min-w-0">
          <div class="flex items-center gap-2 min-w-0">
            <span class="text-sm font-medium text-high truncate">{@team.name}</span>
            <span class={"w-2 h-2 rounded-full shrink-0 #{health_bg_class(@summary.health)}"}></span>
          </div>

          <div class="flex items-center gap-1.5">
            <%= for member <- @team.members do %>
              <.member_status_dot status={member[:status] || :unknown} />
            <% end %>
          </div>

          <span class="text-xs text-low">
            {@summary.member_count} members
          </span>

          <span class="text-xs text-low">
            {@completed}/{@total} tasks
          </span>
        </div>

        <button
          phx-click="inspect_team"
          phx-value-team={@team.name}
          class="px-3 py-1.5 text-xs font-medium bg-raised text-high rounded hover:bg-highlight transition-colors shrink-0"
        >
          Inspect
        </button>
      </div>
    </div>
    """
  end
end
