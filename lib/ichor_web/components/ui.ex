defmodule IchorWeb.UI do
  @moduledoc """
  Component library for ICHOR IV. Import this module to get all UI primitives.

  Layer 0 (base HTML): button, input, select, label
  Layer 1 (semantic primitives): badge, dot, panel_header, close_button,
    empty_panel, nav_icon, agent_actions, agent_info_list
  """

  # Layer 0: Base HTML primitives
  defdelegate button(assigns), to: IchorWeb.UI.Button
  defdelegate input(assigns), to: IchorWeb.UI.Input
  defdelegate select(assigns), to: IchorWeb.UI.Select
  defdelegate label(assigns), to: IchorWeb.UI.Label

  # Layer 1: Semantic primitives
  defdelegate badge(assigns), to: IchorWeb.Components.Primitives.StatusBadge, as: :status_badge
  defdelegate dot(assigns), to: IchorWeb.Components.Primitives.StatusDot, as: :status_dot
  defdelegate panel_header(assigns), to: IchorWeb.Components.Primitives.PanelHeader
  defdelegate close_button(assigns), to: IchorWeb.Components.Primitives.CloseButton
  defdelegate empty_panel(assigns), to: IchorWeb.Components.Primitives.EmptyPanel
  defdelegate nav_icon(assigns), to: IchorWeb.Components.Primitives.NavIcon
  defdelegate agent_actions(assigns), to: IchorWeb.Components.Primitives.AgentActions
  defdelegate agent_info_list(assigns), to: IchorWeb.Components.Primitives.AgentInfoList
end
