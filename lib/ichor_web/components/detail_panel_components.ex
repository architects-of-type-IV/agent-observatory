defmodule IchorWeb.Components.DetailPanelComponents do
  @moduledoc """
  Detail panel components for the right sidebar.
  Shows event detail, task detail, or agent detail depending on selection.
  """

  use Phoenix.Component
  import IchorWeb.DashboardFormatHelpers
  import IchorWeb.DashboardAgentHelpers, only: [agent_recent_events: 3, agent_tasks: 2]

  alias IchorWeb.Presentation

  embed_templates "detail_panel_components/*"

  defp close_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
      <path
        fill-rule="evenodd"
        d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  defp member_status_color(agent), do: Presentation.member_status_dot_class(agent)

  defp task_status_badge("pending"), do: "bg-highlight text-default"
  defp task_status_badge("in_progress"), do: "bg-info/20 text-info"
  defp task_status_badge("completed"), do: "bg-success/20 text-success"
  defp task_status_badge("blocked"), do: "bg-brand/20 text-brand"
  defp task_status_badge("failed"), do: "bg-error/20 text-error"
  defp task_status_badge(_), do: "bg-raised text-low"
end
