defmodule IchorWeb.Components.TeamMessageComponents do
  @moduledoc """
  Team messaging components for the Ichor dashboard.
  """

  use Phoenix.Component
  import IchorWeb.DashboardTeamHelpers
  import IchorWeb.IchorComponents, only: [stable_select: 1]

  attr :teams, :list, required: true
  attr :selected_message_target, :any, default: nil

  def message_composer(assigns) do
    ~H"""
    <form phx-submit="send_targeted_message" class="flex flex-col gap-2">
      <.stable_select
        id="select-message-target"
        name="target"
        phx-change="set_message_target"
        class="ichor-select text-xs py-1.5"
      >
        <option value="">Select target...</option>
        <option value="all_teams">All teams ({length(@teams)} teams)</option>
        <%= for team <- @teams do %>
          <optgroup label={team.name}>
            <option value={"team:#{team.name}"}>
              All members ({length(team.members)})
            </option>
            <%= for member <- (team.members) do %>
              <option value={"member:#{member[:agent_id]}"}>
                {member[:name]} {if detect_role(team, member) == :lead, do: "(lead)", else: ""}
              </option>
            <% end %>
          </optgroup>
        <% end %>
      </.stable_select>
      <div class="flex gap-1">
        <input
          type="text"
          name="content"
          placeholder="Type a message..."
          class="flex-1 ichor-input text-xs py-1.5"
          required
        />
        <button
          type="submit"
          class="ichor-btn ichor-btn-primary shrink-0"
        >
          Send
        </button>
      </div>
    </form>
    """
  end
end
