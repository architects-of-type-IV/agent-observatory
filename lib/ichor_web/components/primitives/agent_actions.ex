defmodule IchorWeb.Components.Primitives.AgentActions do
  @moduledoc """
  Reusable tmux/shutdown button pair for agent control.
  Renders the canonical action set used across dashboard slideout,
  command view, and selected detail panel.
  """

  use Phoenix.Component

  @doc """
  Renders the agent action buttons.

  - Tmux button: shown when `tmux_session` is set
  - Shutdown: always shown, with data-confirm guard

  All buttons fire phx-click events with phx-value-session_id set to `session_id`.
  """
  attr :session_id, :string, required: true
  attr :tmux_session, :string, default: nil

  def agent_actions(assigns) do
    ~H"""
    <button
      :if={@tmux_session}
      phx-click="connect_tmux"
      phx-value-session={@tmux_session}
      class="ichor-btn bg-brand/15 text-brand hover:bg-brand/25"
    >
      Tmux
    </button>
    <button
      phx-click="shutdown_agent"
      phx-value-session_id={@session_id}
      data-confirm="Shut down this agent?"
      class="ichor-btn ichor-btn-muted text-error"
    >
      Shutdown
    </button>
    """
  end
end
