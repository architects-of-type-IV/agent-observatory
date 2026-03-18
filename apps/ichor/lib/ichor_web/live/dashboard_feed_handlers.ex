defmodule IchorWeb.DashboardFeedHandlers do
  @moduledoc """
  Handles feed collapse/expand events.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

  import Phoenix.Component, only: [assign: 3]

  def dispatch("toggle_session_collapse", %{"session_id" => sid}, socket) do
    expanded = socket.assigns.expanded_sessions

    expanded =
      if MapSet.member?(expanded, sid),
        do: MapSet.delete(expanded, sid),
        else: MapSet.put(expanded, sid)

    assign(socket, :expanded_sessions, expanded)
  end

  def dispatch("expand_all", _params, socket) do
    all_keys =
      socket.assigns.feed_groups
      |> Enum.flat_map(&expand_group_keys/1)
      |> MapSet.new()

    assign(socket, :expanded_sessions, all_keys)
  end

  def dispatch("collapse_all", _params, socket) do
    assign(socket, :expanded_sessions, MapSet.new())
  end

  defp expand_group_keys(group) do
    item_keys = Enum.flat_map(group.turns, &expand_turn_keys/1)
    [group.session_id | item_keys]
  end

  defp expand_turn_keys(%{type: :turn} = turn) do
    phase_keys = Enum.map(turn.phases, fn p -> "phase:#{turn.first_event_id}:#{p.index}" end)
    ["turn:#{turn.first_event_id}" | phase_keys]
  end

  defp expand_turn_keys(%{type: :preamble} = preamble) do
    first = List.first(preamble.events)
    phase_keys = Enum.map(preamble.phases, fn p -> "phase:preamble:#{p.index}" end)
    ["preamble:#{first.id}" | phase_keys]
  end

  defp expand_turn_keys(_), do: []
end
