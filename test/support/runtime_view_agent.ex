defmodule Ichor.TestSupport.RuntimeViewAgent do
  @moduledoc false

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
