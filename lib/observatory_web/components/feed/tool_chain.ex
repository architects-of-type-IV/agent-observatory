defmodule ObservatoryWeb.Components.Feed.ToolChain do
  @moduledoc """
  Collapsible tool chain component -- groups consecutive tool calls
  with a summary header. Single tools render inline without a group header.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardFormatHelpers
  alias ObservatoryWeb.DashboardFeedHelpers

  embed_templates "tool_chain/*"
end
