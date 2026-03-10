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
      |> Enum.flat_map(fn g ->
        item_keys =
          g.turns
          |> Enum.flat_map(fn
            %{type: :turn} = turn ->
              turn_key = "turn:#{turn.first_event_id}"

              phase_keys =
                Enum.map(turn.phases, fn p -> "phase:#{turn.first_event_id}:#{p.index}" end)

              [turn_key | phase_keys]

            %{type: :preamble} = preamble ->
              first = List.first(preamble.events)
              preamble_key = "preamble:#{first.id}"
              phase_keys = Enum.map(preamble.phases, fn p -> "phase:preamble:#{p.index}" end)
              [preamble_key | phase_keys]

            _ ->
              []
          end)

        [g.session_id | item_keys]
      end)
      |> MapSet.new()

    assign(socket, :expanded_sessions, all_keys)
  end

  def dispatch("collapse_all", _params, socket) do
    assign(socket, :expanded_sessions, MapSet.new())
  end
end
