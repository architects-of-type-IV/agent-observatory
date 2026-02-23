defmodule ObservatoryWeb.Components.DetailPanelComponents do
  @moduledoc """
  Detail panel components for the right sidebar.
  Shows event detail, task detail, or agent detail depending on selection.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  import ObservatoryWeb.DashboardAgentHelpers, only: [agent_recent_events: 3, agent_tasks: 2]
  import ObservatoryWeb.DashboardTeamHelpers, only: [member_status_color: 1]

  embed_templates "detail_panel_components/*"

  defp close_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
    </svg>
    """
  end

  defp task_status_badge("pending"), do: "bg-zinc-700 text-zinc-400"
  defp task_status_badge("in_progress"), do: "bg-blue-500/20 text-blue-400"
  defp task_status_badge("completed"), do: "bg-emerald-500/20 text-emerald-400"
  defp task_status_badge("blocked"), do: "bg-amber-500/20 text-amber-400"
  defp task_status_badge("failed"), do: "bg-red-500/20 text-red-400"
  defp task_status_badge(_), do: "bg-zinc-800 text-zinc-500"
end
