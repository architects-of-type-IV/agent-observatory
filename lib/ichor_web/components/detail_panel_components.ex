defmodule IchorWeb.Components.DetailPanelComponents do
  @moduledoc """
  Detail panel components for the right sidebar.
  Shows event detail, task detail, or agent detail depending on selection.
  """

  use Phoenix.Component
  import IchorWeb.DashboardFormatHelpers
  import IchorWeb.DashboardAgentHelpers, only: [agent_recent_events: 3, agent_tasks: 2]
  import IchorWeb.Components.Primitives.CloseButton
  import IchorWeb.Components.Primitives.StatusDot

  alias IchorWeb.Presentation

  embed_templates "detail_panel_components/*"

  defp member_status_color(agent), do: Presentation.member_status_dot_class(agent)

  defp task_status_badge("pending"), do: "bg-highlight text-default"
  defp task_status_badge("in_progress"), do: "bg-info/20 text-info"
  defp task_status_badge("completed"), do: "bg-success/20 text-success"
  defp task_status_badge("blocked"), do: "bg-brand/20 text-brand"
  defp task_status_badge("failed"), do: "bg-error/20 text-error"
  defp task_status_badge(_), do: "bg-raised text-low"
end
