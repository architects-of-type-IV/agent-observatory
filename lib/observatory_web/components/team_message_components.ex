defmodule ObservatoryWeb.Components.TeamMessageComponents do
  @moduledoc """
  Team messaging components for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.DashboardTeamHelpers

  attr :teams, :list, required: true
  attr :selected_message_target, :any, default: nil

  def message_composer(assigns) do
    ~H"""
    <div class="bg-zinc-900 border border-zinc-800 rounded-lg p-3">
      <div class="text-xs font-semibold text-zinc-500 uppercase tracking-wider mb-2">
        Send Message
      </div>
      <form phx-submit="send_targeted_message" class="flex flex-col gap-2">
        <%!-- Target selector --%>
        <select
          name="target"
          phx-change="set_message_target"
          class="bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-xs text-zinc-300 focus:border-indigo-500 focus:ring-0 focus:outline-none"
        >
          <option value="">Select target...</option>
          <option value="all_teams">All teams ({length(@teams)} teams)</option>
          <%= for team <- @teams do %>
            <optgroup label={team[:name]}>
              <option value={"team:#{team[:name]}"}>
                All members ({length(team[:members] || [])})
              </option>
              <%= for member <- (team[:members] || []) do %>
                <option value={"member:#{member[:agent_id]}"}>
                  {member[:name]} {if detect_role(team, member) == :lead, do: "(lead)", else: ""}
                </option>
              <% end %>
            </optgroup>
          <% end %>
        </select>
        <%!-- Message input + send --%>
        <div class="flex gap-1">
          <input
            type="text"
            name="content"
            placeholder="Type a message..."
            class="flex-1 bg-zinc-800 border border-zinc-700 rounded px-2 py-1.5 text-xs text-zinc-300 placeholder-zinc-600 focus:border-indigo-500 focus:ring-0 focus:outline-none"
            required
          />
          <button
            type="submit"
            class="px-3 py-1.5 bg-indigo-600/20 text-indigo-400 rounded text-xs hover:bg-indigo-600/30 transition shrink-0"
          >
            Send
          </button>
        </div>
      </form>
    </div>
    """
  end
end
