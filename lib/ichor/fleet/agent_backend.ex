defmodule Ichor.Fleet.AgentBackend do
  @moduledoc """
  Backend liveness checks and graceful/forced termination helpers.

  Abstracts over the different ways to check whether a backing process is
  still alive and how to shut it down, so `AgentProcess` callbacks stay
  free of backend-type dispatch.
  """

  alias Ichor.Infrastructure.Tmux

  @doc """
  Check whether the backing tmux session/pane is still alive.

  Returns `{alive?, tmux_target}` where `tmux_target` is the session/pane
  string (or `""` if the backend carries no tmux reference).
  """
  @spec tmux_alive?(map() | nil) :: {boolean(), String.t()}
  def tmux_alive?(backend) do
    target = get_in(backend, [:session]) || ""
    {Tmux.available?(target), target}
  end

  @doc """
  Terminate the backing resource for the given backend configuration.

  - `:tmux` with a window target (`"session:window"`) — kills only that window.
  - `:tmux` with a session target — kills the entire session.
  - All other backends — no-op.
  """
  @spec terminate(map() | nil) :: :ok
  def terminate(%{type: :tmux, session: session}) when is_binary(session),
    do: terminate_tmux(session)

  def terminate(_backend), do: :ok

  defp terminate_tmux(session) do
    case String.split(session, ":", parts: 2) do
      [_session, _window] -> Tmux.run_command(["kill-window", "-t", session])
      [_session] -> Tmux.run_command(["kill-session", "-t", session])
    end

    :ok
  end
end
