defmodule IchorWeb.Components.FeedComponents do
  @moduledoc """
  Feed/event stream view components. Delegates to focused child modules.
  """

  defdelegate feed_view(assigns), to: IchorWeb.Components.Feed.FeedView
  defdelegate session_group(assigns), to: IchorWeb.Components.Feed.SessionGroup
  defdelegate tool_execution_block(assigns), to: IchorWeb.Components.Feed.ToolExecutionBlock
  defdelegate standalone_event(assigns), to: IchorWeb.Components.Feed.StandaloneEvent
end
