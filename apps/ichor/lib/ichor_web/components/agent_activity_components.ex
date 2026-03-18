defmodule IchorWeb.Components.AgentActivityComponents do
  @moduledoc """
  Agent activity stream components. Delegates to focused child modules.
  """

  defdelegate activity_stream(assigns), to: IchorWeb.Components.AgentActivity.ActivityStream
  defdelegate activity_item(assigns), to: IchorWeb.Components.AgentActivity.ActivityItem
  defdelegate payload_detail(assigns), to: IchorWeb.Components.AgentActivity.PayloadDetail

  defdelegate agent_focus_view(assigns),
    to: IchorWeb.Components.AgentActivity.AgentFocusView
end
