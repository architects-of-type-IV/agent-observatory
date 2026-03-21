defmodule IchorWeb.Components.FeedComponents do
  @moduledoc """
  Feed/event stream view components. Delegates to focused child modules.
  """

  defdelegate feed_view(assigns), to: IchorWeb.Components.Feed.FeedView
  defdelegate session_group(assigns), to: IchorWeb.Components.Feed.SessionGroup
end
