defmodule Ichor.Infrastructure.AgentLifecycle do
  @moduledoc """
  Centralized lifecycle signal emission for agent processes.

  Wraps `Ichor.Signals.emit/2` calls behind named functions so that signal
  names and payload shapes are defined in one place.  Callers never need to
  know the wire names of lifecycle signals.
  """

  @doc "Emit the signal that announces a newly-started agent."
  @spec agent_started(String.t(), atom(), String.t() | nil) :: :ok
  def agent_started(id, role, team) do
    Ichor.Signals.emit(:agent_started, %{session_id: id, role: role, team: team})
  end

  @doc "Emit the signal that announces a paused agent."
  @spec agent_paused(String.t()) :: :ok
  def agent_paused(id) do
    Ichor.Signals.emit(:agent_paused, %{session_id: id})
  end

  @doc "Emit the signal that announces a resumed agent."
  @spec agent_resumed(String.t()) :: :ok
  def agent_resumed(id) do
    Ichor.Signals.emit(:agent_resumed, %{session_id: id})
  end

  @doc "Emit the signal that announces a stopped agent, with the termination reason."
  @spec agent_stopped(String.t(), term()) :: :ok
  def agent_stopped(id, reason) do
    Ichor.Signals.emit(:agent_stopped, %{session_id: id, reason: reason})
  end
end
