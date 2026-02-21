defmodule ObservatoryWeb.Components.Feed.FeedView do
  @moduledoc """
  Main feed view -- always grouped by agent with hierarchy.
  Each agent/session is a collapsible block showing its full event stream.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents
  import ObservatoryWeb.Components.Feed.SessionGroup

  attr :feed_groups, :list, required: true
  attr :visible_events, :list, required: true
  attr :selected_event, :map, default: nil
  attr :event_notes, :map, required: true
  attr :expanded_sessions, :any, default: MapSet.new()
  attr :now, :any, required: true

  def feed_view(assigns) do
    ~H"""
    <div class="p-3 space-y-3">
      <.empty_state
        :if={Enum.empty?(@feed_groups)}
        title="Waiting for agent activity..."
        description="Hook events will stream here in real-time as agents run."
      />

      <.session_group
        :for={group <- @feed_groups}
        group={group}
        selected_event={@selected_event}
        event_notes={@event_notes}
        expanded_sessions={@expanded_sessions}
        now={@now}
        depth={0}
      />
    </div>
    """
  end
end
