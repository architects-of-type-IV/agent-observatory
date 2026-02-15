defmodule ObservatoryWeb.Components.AgentActivityComponents do
  @moduledoc """
  Agent activity stream components. Delegates to focused child modules.
  """

  defdelegate activity_stream(assigns), to: ObservatoryWeb.Components.AgentActivity.ActivityStream
  defdelegate activity_item(assigns), to: ObservatoryWeb.Components.AgentActivity.ActivityItem
  defdelegate payload_detail(assigns), to: ObservatoryWeb.Components.AgentActivity.PayloadDetail

  defdelegate agent_focus_view(assigns),
    to: ObservatoryWeb.Components.AgentActivity.AgentFocusView
end
