defmodule Ichor.TestSupport.RuntimeViewAgent do
  defstruct [
    :agent_id,
    :session_id,
    :short_name,
    :team_name,
    :cwd,
    :channels,
    :tmux_session,
    :status
  ]
end
