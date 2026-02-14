defmodule ObservatoryWeb.ObservatoryComponents do
  @moduledoc """
  Reusable function components for the Observatory dashboard.
  Delegates to focused child modules in components/observatory/.
  """

  defdelegate session_dot(assigns), to: ObservatoryWeb.Components.Observatory.SessionDot
  defdelegate event_type_badge(assigns), to: ObservatoryWeb.Components.Observatory.EventTypeBadge
  defdelegate member_status_dot(assigns), to: ObservatoryWeb.Components.Observatory.MemberStatusDot
  defdelegate empty_state(assigns), to: ObservatoryWeb.Components.Observatory.EmptyState
  defdelegate health_warnings(assigns), to: ObservatoryWeb.Components.Observatory.HealthWarnings
  defdelegate model_badge(assigns), to: ObservatoryWeb.Components.Observatory.ModelBadge
  defdelegate toast_container(assigns), to: ObservatoryWeb.Components.Observatory.ToastContainer
  defdelegate message_thread(assigns), to: ObservatoryWeb.Components.Observatory.MessageThread
end
