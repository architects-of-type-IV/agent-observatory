defmodule ObservatoryWeb.Components.FeedComponents do
  @moduledoc """
  Feed/event stream view components. Delegates to focused child modules.
  """

  defdelegate feed_view(assigns), to: ObservatoryWeb.Components.Feed.FeedView
  defdelegate session_group(assigns), to: ObservatoryWeb.Components.Feed.SessionGroup
  defdelegate tool_execution_block(assigns), to: ObservatoryWeb.Components.Feed.ToolExecutionBlock
  defdelegate standalone_event(assigns), to: ObservatoryWeb.Components.Feed.StandaloneEvent
end
