defmodule IchorWeb.Components.MessagesComponents do
  @moduledoc """
  Messages/threads view component for the Ichor dashboard.
  """

  use Phoenix.Component
  import IchorWeb.IchorComponents
  import IchorWeb.DashboardMessageHelpers

  attr :messages, :list, required: true
  attr :message_threads, :list, required: true
  attr :search_messages, :string, default: ""
  attr :collapsed_threads, :map, required: true
  attr :now, :any, required: true

  def messages_view(assigns) do
    ~H"""
    <div class="p-4 max-w-4xl mx-auto">
      <.empty_state
        :if={@messages == []}
        title="No inter-agent messages yet"
        description="Messages appear when agents use the SendMessage tool for team coordination"
      />

      <div :if={@messages != []} class="space-y-4">
        <%!-- Search and Filter Controls --%>
        <div class="flex items-center gap-2 pb-3 border-b border-border">
          <form phx-change="search_messages" class="flex-1">
            <input
              type="text"
              name="q"
              value={@search_messages || ""}
              placeholder="Search messages by content or participant..."
              autocomplete="off"
              phx-debounce="150"
              class="w-full bg-raised border border-border-subtle rounded px-2.5 py-1 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0 focus:outline-none"
            />
          </form>
          <button
            phx-click="expand_all_threads"
            class="text-xs px-2 py-1 rounded bg-raised hover:bg-highlight text-default hover:text-high transition whitespace-nowrap"
            title="Expand all threads"
          >
            Expand All
          </button>
          <button
            phx-click="collapse_all_threads"
            class="text-xs px-2 py-1 rounded bg-raised hover:bg-highlight text-default hover:text-high transition whitespace-nowrap"
            title="Collapse all threads"
          >
            Collapse All
          </button>
        </div>

        <%!-- Message Threads --%>
        <div :for={thread <- @message_threads} class="space-y-4">
          <.message_thread
            thread={thread}
            now={@now}
            collapsed={Map.get(@collapsed_threads, participant_key(thread.participants), false)}
          />
        </div>
      </div>
    </div>
    """
  end
end
