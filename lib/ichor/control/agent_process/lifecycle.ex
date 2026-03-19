defmodule Ichor.Control.AgentProcess.Lifecycle do
  @moduledoc """
  Liveness and lifecycle signal helpers for agent processes.
  """

  alias Ichor.Gateway.Channels.Tmux

  @liveness_interval :timer.seconds(15)

  @doc "Schedule a liveness check for the calling process after the default interval."
  @spec schedule_liveness_check() :: reference()
  def schedule_liveness_check do
    Process.send_after(self(), :check_liveness, @liveness_interval)
  end

  @doc "Check if the tmux backend session is still alive. Returns `{alive?, tmux_target}`."
  @spec tmux_alive?(map() | nil) :: {boolean(), String.t()}
  def tmux_alive?(backend) do
    tmux_target = get_in(backend, [:session]) || ""
    {Tmux.available?(tmux_target), tmux_target}
  end

  @doc "Terminate the tmux backend for a session or window."
  @spec terminate_backend(map() | nil) :: :ok | {:error, term()}
  def terminate_backend(%{type: :tmux, session: session}) when is_binary(session) do
    if String.contains?(session, ":") do
      Tmux.run_command(["kill-window", "-t", session])
    else
      Tmux.run_command(["kill-session", "-t", session])
    end
  end

  def terminate_backend(_backend), do: :ok

  @doc "Broadcast a lifecycle event signal."
  @spec broadcast(
          {:agent_started, String.t(), map()}
          | {:agent_paused, String.t()}
          | {:agent_resumed, String.t()}
          | {:agent_stopped, String.t(), term()}
        ) :: :ok
  def broadcast({:agent_started, id, %{role: role, team: team}}) do
    Ichor.Signals.emit(:agent_started, %{session_id: id, role: role, team: team})
  end

  def broadcast({:agent_paused, id}) do
    Ichor.Signals.emit(:agent_paused, %{session_id: id})
  end

  def broadcast({:agent_resumed, id}) do
    Ichor.Signals.emit(:agent_resumed, %{session_id: id})
  end

  def broadcast({:agent_stopped, id, reason}) do
    Ichor.Signals.emit(:agent_stopped, %{session_id: id, reason: reason})
  end
end
