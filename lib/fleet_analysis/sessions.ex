defmodule FleetAnalysis.Sessions do
  @moduledoc """
  Derives sessions from a raw event log.

  A "session" is not stored anywhere — it is inferred by grouping events on
  `{source_app, session_id}` and summarising each group. That is deliberate: the
  event log is append-only and authoritative, so anything derived from it cannot
  drift out of sync with reality the way a separately maintained session table
  would.

  ## Sessions with no events

  A tmux session that exists but has never emitted an event is invisible to a
  pure event query — and a freshly spawned agent that failed before its first
  event is exactly the case you most want to see. Pass `:tmux` with the live
  session names and those appear too, with zero events, rather than being
  silently absent.
  """

  alias FleetAnalysis.Event

  @typedoc "A derived session summary."
  @type session :: %{
          source_app: String.t() | nil,
          session_id: String.t(),
          event_count: non_neg_integer(),
          latest_event: map(),
          first_event: map(),
          ended?: boolean(),
          model: String.t() | nil,
          permission_mode: term(),
          cwd: String.t() | nil
        }

  @doc """
  Group events into session summaries, newest activity first.

  ## Options

    * `:tmux` — live tmux session names, so sessions with no events still appear
    * `:now` — the clock, for the synthesised entries; defaults to now
  """
  @spec active_sessions([Event.t()], keyword()) :: [session()]
  def active_sessions(events, opts \\ []) do
    tmux_sessions = Keyword.get(opts, :tmux, [])
    now = Keyword.get(opts, :now, DateTime.utc_now())

    from_events(events) ++ tmux_only(events, tmux_sessions, now)
  end

  defp from_events(events) do
    events
    |> Enum.group_by(&{Event.get(&1, :source_app), Event.get(&1, :session_id)})
    |> Enum.map(fn {{app, sid}, group} -> summarise(app, sid, group) end)
    |> Enum.sort_by(&Event.timestamp(&1.latest_event), {:desc, DateTime})
  end

  defp summarise(app, session_id, events) do
    sorted = Event.newest_first(events)
    latest = hd(sorted)

    %{
      source_app: app,
      session_id: session_id,
      event_count: length(events),
      latest_event: latest,
      first_event: List.last(sorted),
      ended?: Enum.any?(events, &(Event.type(&1) == :SessionEnd)),
      model: Event.find_model(events),
      permission_mode: Event.get(latest, :permission_mode),
      cwd: Event.get(latest, :cwd) || Event.find_cwd(events)
    }
  end

  # Only synthesise entries for tmux sessions no event has ever mentioned;
  # otherwise a session would appear twice, once real and once empty.
  defp tmux_only(events, tmux_sessions, now) do
    known =
      events
      |> Enum.map(&Event.get(&1, :tmux_session))
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    tmux_sessions
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.map(fn name ->
      %{
        source_app: name,
        session_id: name,
        event_count: 0,
        latest_event: %{inserted_at: now},
        first_event: %{inserted_at: now},
        ended?: false,
        model: nil,
        permission_mode: nil,
        cwd: nil,
        tmux_session: name
      }
    end)
  end
end
