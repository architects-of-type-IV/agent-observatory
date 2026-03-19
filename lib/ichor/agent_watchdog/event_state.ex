defmodule Ichor.AgentWatchdog.EventState do
  @moduledoc """
  Pure state transformations for session activity tracking.

  No side effects. All functions take and return plain maps.
  """

  @doc "Extract team_name from a SessionStart event payload."
  @spec extract_team_name(map()) :: String.t() | nil
  def extract_team_name(%{payload: %{"team_name" => name}}) when is_binary(name), do: name
  def extract_team_name(_event), do: nil

  @doc "Apply a session event to the sessions map. Returns updated sessions map."
  @spec update_session_activity(map(), map()) :: map()
  def update_session_activity(%{hook_event_type: :SessionStart} = event, sessions) do
    team_name = extract_team_name(event)

    Map.put(sessions, event.session_id, %{
      last_event_at: DateTime.utc_now(),
      team_name: team_name
    })
  end

  def update_session_activity(%{hook_event_type: :SessionEnd} = event, sessions) do
    Map.delete(sessions, event.session_id)
  end

  def update_session_activity(event, sessions) do
    touch_session_activity(event.session_id, sessions)
  end

  @doc "Update last_event_at for a known session. Returns sessions map unchanged if session unknown."
  @spec touch_session_activity(String.t(), map()) :: map()
  def touch_session_activity(session_id, sessions) do
    if Map.has_key?(sessions, session_id) do
      Map.update!(sessions, session_id, &%{&1 | last_event_at: DateTime.utc_now()})
    else
      sessions
    end
  end
end
